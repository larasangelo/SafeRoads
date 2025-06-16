import admin from "firebase-admin";
import { readFileSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { getMessaging } from "firebase-admin/messaging";
import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import pkg from "pg";

const { Pool } = pkg;

// ES module workaround for `__dirname`
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables
dotenv.config();

// PostgreSQL connection pool
const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT,
});

// Gracefully handle database connection pool termination
const closeDatabaseConnection = async () => {
  try {
    console.log("Closing database connection...");
    await pool.end();
    console.log("Database connection closed.");
  } catch (err) {
    console.error("Error closing database connection:", err);
  }
};

//Function to test if we can get raster values for a single point
const getRasterValue = async (point, selectedSpecies = []) => {
  try {
    if (!point || !point.lat || !point.lon) {
      throw new Error("Invalid coordinates");
    }

    if (!Array.isArray(selectedSpecies) || selectedSpecies.length === 0) {
      throw new Error("No species selected");
    }

    // Create SQL snippet to UNION ALL risk queries for each species
    const speciesUnion = selectedSpecies.map(species =>
      `SELECT '${species.replace(/'/g, "''")}' AS species_name,
              COALESCE(ST_Value(r_${species.toLowerCase()}.rast, 1, ST_SetSRID(ST_MakePoint(${point.lon}, ${point.lat}), 4326)), 0) AS value
       FROM ${species.toLowerCase()} r_${species.toLowerCase()}
       WHERE ST_Intersects(r_${species.toLowerCase()}.rast, ST_SetSRID(ST_MakePoint(${point.lon}, ${point.lat}), 4326))`
    ).join(" UNION ALL ");

    const query = `
      SELECT 
        MAX(value) AS risk_value,
        ARRAY_AGG(species_name) FILTER (WHERE value > 0) AS risky_species
      FROM (
        ${speciesUnion}
      ) AS species_risks;
    `;

    const result = await pool.query(query);
    const row = result.rows[0];

    return {
      risk_value: row?.risk_value || 0,
      risky_species: row?.risky_species || []
    };
  } catch (err) {
    console.error("Error in getRasterValue:", err);
    return { risk_value: 0, risky_species: [] };
  }
};

// Route computation function
const getRoute = async (start, end, lowRisk, selectedSpecies) => {
  try {
    // Get nearest node to start
    const startNodeQuery = `
      SELECT id FROM ways_vertices_pgr
      ORDER BY the_geom <-> ST_SetSRID(ST_Point(${start.lon}, ${start.lat}), 4326)
      LIMIT 1;
    `;
    const startNode = await pool.query(startNodeQuery);

    // Get nearest node to end
    const endNodeQuery = `
      SELECT id FROM ways_vertices_pgr
      ORDER BY the_geom <-> ST_SetSRID(ST_Point(${end.lon}, ${end.lat}), 4326)
      LIMIT 1;
    `;
    const endNode = await pool.query(endNodeQuery);

    // Calculate dynamic buffer
    const R = 6371;
    const dLat = (end.lat - start.lat) * (Math.PI / 180);
    const dLon = (end.lon - start.lon) * (Math.PI / 180);
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(start.lat * (Math.PI / 180)) * Math.cos(end.lat * (Math.PI / 180)) * Math.sin(dLon / 2) ** 2;
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distanceKm = R * c;
    const bufferDistance = Math.min(0.02 + distanceKm * 0.01, 1);
    console.log("bufferDistance", bufferDistance);

    const minLat = Math.min(start.lat, end.lat) - bufferDistance;
    const maxLat = Math.max(start.lat, end.lat) + bufferDistance;
    const minLon = Math.min(start.lon, end.lon) - bufferDistance;
    const maxLon = Math.max(start.lon, end.lon) + bufferDistance;

    if(bufferDistance < 0.5){
      console.log("bufferDistance:", bufferDistance, "< 0.5, entra no if");

      const createTempTableQuery = `
       CREATE TEMP TABLE temp_ways (
         gid INTEGER,
         source INTEGER,
         target INTEGER,
         cost DOUBLE PRECISION,
         reverse_cost DOUBLE PRECISION,
         the_geom GEOMETRY,
         length_m DOUBLE PRECISION,
         maxspeed_forward DOUBLE PRECISION,
         maxspeed_backward DOUBLE PRECISION,
         risk_value DOUBLE PRECISION DEFAULT NULL,
         species TEXT[] DEFAULT '{}'
       );
 
       INSERT INTO temp_ways (gid, source, target, cost, reverse_cost, the_geom, length_m, maxspeed_forward, maxspeed_backward)
       SELECT w.gid, w.source, w.target, w.cost, w.reverse_cost, w.the_geom, w.length_m,
              w.maxspeed_forward, w.maxspeed_backward
       FROM ways w
       WHERE ST_Intersects(
         w.the_geom,
         ST_MakeEnvelope(${minLon}, ${minLat}, ${maxLon}, ${maxLat}, 4326)
       );
     `;
      await pool.query(createTempTableQuery);
      console.log("Temporary table created with bounding box.");
  
      // Update temp_ways with raster values and species lists
      const updateTempTableWithRasterQuery = `
        UPDATE temp_ways
        SET
            risk_value = subquery.risk_value,
            species = subquery.species
        FROM (
            SELECT
                w_inner.gid,
                MAX(species_data.value) AS risk_value,
                ARRAY_AGG(DISTINCT species_data.species_name) AS species  -- Store all species
            FROM temp_ways w_inner
            JOIN LATERAL (
                ${selectedSpecies.map(species =>
                    `SELECT '${species.replace(/'/g, "''")}' AS species_name,
                    COALESCE(ST_Value(r_${species.toLowerCase()}.rast, 1, ST_Centroid(w_inner.the_geom)), 0) AS value
                    FROM ${species.toLowerCase()} r_${species.toLowerCase()}
                    WHERE ST_Intersects(r_${species.toLowerCase()}.rast, w_inner.the_geom)`
                ).join(" UNION ALL ")}
            ) AS species_data ON TRUE
            GROUP BY w_inner.gid
        ) AS subquery
        WHERE temp_ways.gid = subquery.gid;
      `;
      await pool.query(updateTempTableWithRasterQuery);
      console.log("Raster values and species info added to the temporary table.");

    }else{
      console.log("bufferDistance:", bufferDistance, "> 0.5, entra no else");

      await pool.query(`
        CREATE TEMP TABLE temp_ways AS
        SELECT gid, source, target, the_geom, maxspeed_forward, maxspeed_backward, risk_value, species, cost, reverse_cost, length_m
        FROM get_ways_with_risk($1)
        WHERE ST_Intersects(
          the_geom,
          ST_MakeEnvelope(${minLon}, ${minLat}, ${maxLon}, ${maxLat}, 4326)
        );
      `, 
      [selectedSpecies.length > 0 ? selectedSpecies : null]);

      console.log("Temporary table created with bounding box and risk.");
    }

    // Run risk-aware route
    const route = await pool.query(`
      SELECT *,
        ST_AsGeoJSON(the_geom) AS geojson,
        maxspeed_forward, maxspeed_backward, species, length_m
      FROM pgr_dijkstra(
        'SELECT gid AS id, source, target,
                cost * (1 + COALESCE(risk_value, 0) * 4) AS cost,
                reverse_cost * (1 + COALESCE(risk_value, 0) * 4) AS reverse_cost
        FROM temp_ways',
        ${startNode.rows[0].id}, ${endNode.rows[0].id},
        directed := true
      ) AS route
      JOIN temp_ways ON route.edge = temp_ways.gid
      ORDER BY route.seq;
    `);

    console.log("Adjusted route fetched");
    
    // Run default route if needed
    if (!lowRisk) {
      const routeDefault = await pool.query(`
        SELECT *,
          ST_AsGeoJSON(the_geom) AS geojson,
          maxspeed_forward, maxspeed_backward, length_m
        FROM pgr_dijkstra(
          'SELECT gid AS id, source, target, cost, reverse_cost FROM temp_ways',
          ${startNode.rows[0].id}, ${endNode.rows[0].id},
          directed := true
        ) AS route
        JOIN temp_ways ON route.edge = temp_ways.gid
        ORDER BY route.seq;
      `);

      console.log("Default route fetched");

      return {
        adjustedRoute: route.rows.map(r => ({ ...r, species: r.species || [] })),
        defaultRoute: routeDefault.rows
      };
    }

    return {
      adjustedRoute: route.rows.map(r => ({ ...r, species: r.species || [] }))
    };
  } catch (err) {
    console.error(err);
  }
};

//  São Bento de Sexta Freita
// 30095, 951623,

// Firebase Admin initialization
admin.initializeApp({
  credential: admin.credential.cert(
    JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, "utf8"))
    // JSON.parse(
    //   readFileSync(
    //     path.join(__dirname, "flutter-saferoads-firebase-adminsdk-sekrk-712d669273.json"),
    //     "utf8"
    //   )
    // )
  ),
  projectId: "flutter-saferoads",
});

// Express app setup
const app = express();
app.use(express.json());
app.use(cors({ origin: "*" }));

// Serve static files from the 'tiles' directory
// app.use('/tiles', express.static(path.join(__dirname, 'tiles')));

// Calls Firebase Cloud Messaging for Notifications
app.post("/send", (req, res) => {
  // Timeout de 5 segundos para testar
  // setTimeout( function () {
    const receivedToken = req.body.fcmToken;
    const receivedtitle = req.body.title;
    const receivedbody = req.body.body;
    const receivedButton = req.body.button;
    const receivedChangeRoute = req.body.changeRoute;
    const receivedType = req.body.type;

    const message = {
      token: receivedToken,
      data: {
        title: String(receivedtitle),
        body: String(receivedbody),
        button: String(receivedButton),
        changeRoute: String(receivedChangeRoute),
        type: String(receivedType || "")
      },
      android: {
        priority: "high",
      },
      apns: {
        headers: {
          "apns-priority": "10"
        },
        payload: {
          aps: {
            contentAvailable: true, // This is important for background updates
          }
        }
      }
    };

    getMessaging()
      .send(message)
      .then((response) => {
        res.status(200).json({
          message: "Successfully sent message",
          token: receivedToken,
        });
        console.log(`Successfully sent message: ${response}`);
      })
      .catch((error) => {
        res.status(400).json({ error: error.message });
        console.log("Error sending message:", error);
      });

  //   }, 5000
  // )
});

//Calls the getRoute function to get the routes (optimal and default or just optimal)
app.post("/route", async (req, res) => {
  try {
    const { start, end, lowRisk, selectedSpecies } = req.body;
    const routes = await getRoute(start, end, lowRisk, selectedSpecies);

    console.log('Out of the getRoute function');

    let responseData = {};
    let allRoutes = {};

    for (const [key, route] of Object.entries(routes)) {
      if (!route || route.length === 0) {
        console.log(`Skipping route: ${key}, no valid data found.`);
        continue;
      }

      // We'll build a list of segments, not just individual points
      let routeSegments = [];
      let totalDistance = 0; // in meters
      let totalTime = 0; // in seconds

      let hasRisk = false; // Flag for risk detection

      route.forEach((row, index) => {
        const geojson = JSON.parse(row.geojson);
        const segmentDistance = parseFloat(row.length_m);

        const speed =
          row.reverse_cost === -1 ? row.maxspeed_forward : row.maxspeed_backward;

        if (!speed || speed <= 0) {
          console.warn("Invalid speed value for segment, skipping:", row);
          return;
        }

        const speedMps = (speed * 1000) / 3600;
        const segmentTimeSeconds = segmentDistance / speedMps;
        totalTime += segmentTimeSeconds;
        totalDistance += segmentDistance;

        if (geojson.type === "LineString") {
          const coordinates = geojson.coordinates;
          
          // Determine the correct order of coordinates for this segment
          let currentSegmentCoords = coordinates;
          if (index === 0) {
            const startDistanceToFirst = calculateDistance(start.lat, start.lon, coordinates[0][1], coordinates[0][0]);
            const startDistanceToLast = calculateDistance(start.lat, start.lon, coordinates[coordinates.length - 1][1], coordinates[coordinates.length - 1][0]);
            if (startDistanceToLast < startDistanceToFirst) {
              currentSegmentCoords = coordinates.slice().reverse();
            }
          } else {
            // For now, let's assume `routeSegments` accurately represents consecutive segments
            // and we can infer the connection. If the routing API guarantees sorted segments,
            // this simplifies. If not, you might need a more robust path reconstruction.
            const lastPointOfPreviousSegment = routeSegments.length > 0 ? routeSegments[routeSegments.length - 1].end : null;
            if (lastPointOfPreviousSegment) {
                const distanceToFirst = calculateDistance(lastPointOfPreviousSegment.lat, lastPointOfPreviousSegment.lon, coordinates[0][1], coordinates[0][0]);
                const distanceToLast = calculateDistance(lastPointOfPreviousSegment.lat, lastPointOfPreviousSegment.lon, coordinates[coordinates.length - 1][1], coordinates[coordinates.length - 1][0]);
                if (distanceToLast < distanceToFirst) {
                    currentSegmentCoords = coordinates.slice().reverse();
                }
            }
          }

          // Now, iterate through the coordinates of the current LineString
          // and create sub-segments (point-to-point)
          for (let i = 0; i < currentSegmentCoords.length - 1; i++) {
            const startCoord = currentSegmentCoords[i];
            const endCoord = currentSegmentCoords[i + 1];
            const microSegmentDistance = calculateDistance(startCoord[1], startCoord[0], endCoord[1], endCoord[0]);

            const segment = {
              start: { lat: startCoord[1], lon: startCoord[0] },
              end: { lat: endCoord[1], lon: endCoord[0] },
              // Assign the raster value and species directly to this micro-segment
              raster_value: row.risk_value,
              species: row.risk_value > 0.3 && row.species && row.species.length > 0 ? row.species : [],
              // For a small point-to-point segment, its time is a fraction of the full geojson segment time.
              // Calculate this fraction based on distance.
              // This is a more precise way to distribute time across micro-segments.
              time_to_next_seconds: (microSegmentDistance / segmentDistance) * segmentTimeSeconds,
              // If you only want the time for the *full original geojson segment* to be carried,
              // then you could pass `segmentTimeSeconds` here, but that would be less granular for Flutter.
              // It depends on whether Flutter's `routeCoordinates` array represents
              // individual points or segment objects.
              segment_distance: microSegmentDistance, 
            };
            routeSegments.push(segment);

            if (row.risk_value > 2) hasRisk = true;
          }
        }
      });

      const getRiskCategory = (value) => {
        if (value >= 0.6) return 'high';
        if (value >= 0.5) return 'mediumHigh';
        if (value >= 0.3) return 'medium';
        if (value >= 0.2) return 'mediumLow';
        return 'low';
      };

      let maxRiskValue = 0;
      let riskCategory = '';
      let distanceAtMaxRisk = 0;

      // Step 1: Find max risk value
      routeSegments.forEach(seg => {
        if (seg.raster_value > maxRiskValue) {
          maxRiskValue = seg.raster_value;
        }
      });

      // Step 2: Identify risk category of the max value
      riskCategory = getRiskCategory(maxRiskValue);

      // Step 3: Sum distance of all segments in the same risk category
      routeSegments.forEach(seg => {
        if (getRiskCategory(seg.raster_value) === riskCategory) {
          distanceAtMaxRisk += seg.segment_distance;
        }
      });

      // Format the distance and time as before
      const formattedDistance =
        totalDistance < 1000
          ? `${totalDistance.toFixed(0)} meters`
          : `${(totalDistance / 1000).toFixed(2)} km`;

      const totalHours = Math.floor(totalTime / 3600);
      const remainingSeconds = totalTime % 3600;
      const totalMinutes = Math.round(remainingSeconds / 60);
      const formattedTime =
        totalHours > 0
          ? `${totalHours}h ${totalMinutes}min`
          : `${totalMinutes} min`;

      // Format distanceAtMaxRisk similarly:
      const formattedDistanceAtMaxRisk = 
        distanceAtMaxRisk < 1000
          ? `${Math.round(distanceAtMaxRisk)} meters`
          : `${(distanceAtMaxRisk / 1000).toFixed(2)} km`;

      // Store route data for comparison (adjusting for new structure)
      allRoutes[key] = routeSegments;

      // console.log('Route Segments for', key, ':', routeSegments);
      console.log('Distance at Max Risk for', key, ':', formattedDistanceAtMaxRisk);
      console.log('Max Risk Value for', key, ':', maxRiskValue);

      // Store results in responseData
      responseData[key] = {
        // Change 'route' to 'segments' to reflect new structure
        segments: routeSegments, // Changed from 'route' to 'segments'
        distance: formattedDistance,
        time: formattedTime,
        hasRisk,
        maxRiskValue,
        distanceAtMaxRisk: formattedDistanceAtMaxRisk,
      };
    }

    // Check if all routes are identical (adjusting for new structure)
    const routeKeys = Object.keys(allRoutes);
    if (
      routeKeys.length > 1 &&
      JSON.stringify(allRoutes[routeKeys[0]]) === JSON.stringify(allRoutes[routeKeys[1]])
    ) {
      console.log("Duplicate routes detected, returning only the default route.");
      responseData = { default: responseData[routeKeys[0]] };
    }

    res.status(200).json(responseData);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Test if we can get the raster_values for a single point
app.post("/raster", async (req, res) => {
  const { point, selectedSpecies } = req.body;

  try {
    const response = await getRasterValue(point, selectedSpecies);
    res.status(200).json(response);
  } catch (err) {
    console.error("Error fetching raster value:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Helper function to calculate distance between two coordinates
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371e3; // Earth's radius in meters
  const rad = (deg) => (deg * Math.PI) / 180;
  const φ1 = rad(lat1);
  const φ2 = rad(lat2);
  const Δφ = rad(lat2 - lat1);
  const Δλ = rad(lon2 - lon1);

  const a =
    Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // Distance in meters
}

//Calls the Photon Geocoder API, that transforms the inputed address in coordinates
app.post("/geocode", async (req, res) => {
  const { address } = req.body;
  console.log("address", address);
  if (!address) {
    return res.status(400).json({ error: "Address is required" });
  }

  try {
    const response = await fetch(
      `https://photon.komoot.io/api/?q=${encodeURIComponent(address)}`
    );
    if (response.ok) {
      const data = await response.json();
      if (data.features && data.features.length > 0) {
        const lat = data.features[0].geometry.coordinates[1];
        const lon = data.features[0].geometry.coordinates[0];
        return res.status(200).json({ lat, lon });
      } else {
        return res.status(404).json({ error: "Address not found" });
      }
    } else {
      return res.status(response.status).json({ error: "Failed to fetch coordinates" });
    }
  } catch (err) {
    console.error("Error fetching coordinates:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});


//Calls the Photon Geocoder API that gets the various options for the sugestion box
app.get("/search", async (req, res) => {
  const { query, limit = 5, lang = 'en' } = req.query;
  console.log("query:", query)

  if (!query) {
    return res.status(400).json({ error: "Query parameter is required" });
  }

  try {
    const url = `https://photon.komoot.io/api/?q=${encodeURIComponent(query)},portugal&limit=${limit}&lang=${lang}`;
    const response = await fetch(url);
    
    const text = await response.text(); // Get raw response
    // console.log("Raw API response:", text); 
  
    const data = JSON.parse(text); // Now try parsing JSON
    res.status(200).json(data);
  } catch (err) {
    console.error("Error fetching search results:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

app.post("/update-position", async (req, res) => {
  const { userId, lat, lon } = req.body;
  console.log(`User ${userId} updated position: ${lat}, ${lon}`);
  
  // Optionally, store or process the position
  res.status(200).json({ message: "Position updated successfully" });
});


// Shutdown handler to ensure clean exit
const shutdown = async () => {
  await closeDatabaseConnection();
  process.exit(0);
};

process.on("SIGINT", shutdown); // Handle Ctrl+C
process.on("SIGTERM", shutdown); // Handle termination signals

// Start the server
app.listen(3001, () => {
  console.log("Server started on port 3001");
});
