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
const getRasterValue = async (start) => {
  try{
    const rasterValue = await pool.query(`
      SELECT ST_VALUE(rast,1,ST_SetSRID(ST_MakePoint(${start.lon}, ${start.lat}), 4326)) AS raster_value
      FROM public.raster_table
      WHERE ST_Intersects(rast,ST_SetSRID(ST_MakePoint(${start.lon}, ${start.lat}), 4326));
    `)
    // 41.84083,-7.89093 // Test with an higher value
    const value = rasterValue.rows[0]?.raster_value;
    // console.log(value); 
    return value;
  } catch (err){
    console.error(err);
  }
};

// Route computation function
const getRoute = async (start, end, lowRisk, selectedSpecies) => {
  try {
    // Get start and end nodes
    const startNodeQuery = `
      SELECT id, ST_Distance(the_geom::geography, ST_SetSRID(ST_Point(${start.lon}, ${start.lat}), 4326)::geography) AS dist
      FROM ways_vertices_pgr
      ORDER BY dist ASC
      LIMIT 1;
    `;
    const startNode = await pool.query(startNodeQuery);
    // console.log("startNode", startNode.rows[0].id);

    const endNodeQuery = `
      SELECT id, ST_Distance(the_geom::geography, ST_SetSRID(ST_Point(${end.lon}, ${end.lat}), 4326)::geography) AS dist
      FROM ways_vertices_pgr
      ORDER BY dist ASC
      LIMIT 1;
    `;
    const endNode = await pool.query(endNodeQuery);
    // console.log("endNode", endNode.rows[0].id);

    // Calculate bounding box
    const bufferDistance = 0.05;
    const minLat = Math.min(start.lat, end.lat) - bufferDistance;
    const maxLat = Math.max(start.lat, end.lat) + bufferDistance;
    const minLon = Math.min(start.lon, end.lon) - bufferDistance;
    const maxLon = Math.max(start.lon, end.lon) + bufferDistance;

    // console.log("minLat", minLat);
    // console.log("maxLat", maxLat);
    // console.log("minLon", minLon);
    // console.log("maxLon", maxLon);

    await pool.query("DROP TABLE IF EXISTS temp_ways;");
    console.log("Temporary table dropped.");
    // Create a temporary table to store road segments and species info
    const createTempTableQuery = `
      CREATE TABLE temp_ways (
        gid INTEGER,
        source INTEGER,
        target INTEGER,
        cost DOUBLE PRECISION,
        reverse_cost DOUBLE PRECISION,
        the_geom GEOMETRY,
        length_m DOUBLE PRECISION,
        maxspeed_forward DOUBLE PRECISION,
        maxspeed_backward DOUBLE PRECISION,
        raster_value DOUBLE PRECISION DEFAULT NULL,
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
          raster_value = subquery.raster_value,
          species = subquery.species
      FROM (
          SELECT
              w_inner.gid,
              MAX(species_data.value) AS raster_value,
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

    // Step 3: Run the pgr_dijkstra query on the temp table
    const routeQuery = `
      SELECT *,
            ST_AsGeoJSON(the_geom) AS geojson,
            maxspeed_forward,
            maxspeed_backward,
            species
      FROM pgr_dijkstra(
        'SELECT gid AS id, 
                source, 
                target,
                cost * (1 + raster_value * 4) AS cost,
                reverse_cost * (1 + raster_value * 4) AS reverse_cost
        FROM temp_ways',
        ${startNode.rows[0].id}, 
        ${endNode.rows[0].id},
        directed := true
      ) AS route
      JOIN temp_ways ON route.edge = temp_ways.gid
      ORDER BY route.seq;
    `;
    const route = await pool.query(routeQuery);

    // Step 4: If the user doesn't want only the low-risk route, return the default route
    if (!lowRisk) {
      console.log("Fetching default route.");
      const routeDefault = `
        SELECT *,
        ST_AsGeoJSON(the_geom) AS geojson,
        maxspeed_forward,
        maxspeed_backward
        FROM pgr_dijkstra(
          'SELECT gid AS id, source, target, cost, reverse_cost, maxspeed_forward, maxspeed_backward FROM ways',
          ${startNode.rows[0].id}, ${endNode.rows[0].id},
          directed := true
        ) AS route
        JOIN temp_ways ON route.edge = temp_ways.gid
        ORDER BY route.seq;
      `;

      const routeUnaware = await pool.query(routeDefault);
      console.log("Default route fetched.");

      // Clean up the temporary table
      // await pool.query("DROP TABLE IF EXISTS temp_ways;");
      // console.log("Temporary table dropped.");

      return { 
        adjustedRoute: route.rows.map(row => ({
          ...row,
          species: row.species || []  // Ensure species info is included
        })), 
        defaultRoute: routeUnaware.rows 
      };
    } else {
      // await pool.query("DROP TABLE IF EXISTS temp_ways;");
      return { 
        adjustedRoute: route.rows.map(row => ({
          ...row,
          species: row.species || []  // Ensure species info is included
        })) 
      };
    }
  } catch (err) {
    console.error(err);
  }
};

//  São Bento de Sexta Freita
// 30095, 951623,

// Firebase Admin initialization
admin.initializeApp({
  credential: admin.credential.cert(
    JSON.parse(
      readFileSync(
        path.join(__dirname, "flutter-saferoads-firebase-adminsdk-sekrk-712d669273.json"),
        "utf8"
      )
    )
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

    const message = {
      token: receivedToken,
      notification: {
        body: receivedbody,
        title: receivedtitle,
      },
      data: {
        button: receivedButton,
        changeRoute: receivedChangeRoute
      },
      android: {
        notification: {
          sound: "default"
        }
      },
      apns: {
        payload: {
          aps: {
            sound: "default"
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
        // messageCounter++; // Increment counter
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

    let responseData = {};
    let allRoutes = {}; // Store routes for comparison

    for (const [key, route] of Object.entries(routes)) {
      if (!route || route.length === 0) {
        return res.status(404).json({ error: "Route not found" });
      }

      let routePoints = [];
      let totalDistance = 0; // in meters
      let totalTime = 0; // in hours
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
        const segmentTime = segmentDistance / speedMps;
        totalTime += segmentTime / 3600;
        totalDistance += segmentDistance;

        if (geojson.type === "LineString") {
          const coordinates = geojson.coordinates;
          const firstCoord = coordinates[0];
          const lastCoord = coordinates[coordinates.length - 1];

          const startDistanceToFirst = calculateDistance(
            start.lat,
            start.lon,
            firstCoord[1],
            firstCoord[0]
          );
          const startDistanceToLast = calculateDistance(
            start.lat,
            start.lon,
            lastCoord[1],
            lastCoord[0]
          );

          const processCoordinates = (coords) => {
            coords.forEach(([lon, lat]) => {
              if (row.raster_value > 2) hasRisk = true;

              const existingPointIndex = routePoints.findIndex(
                (point) => point.lat === lat && point.lon === lon
              );

              if (existingPointIndex !== -1) {
                // If same coordinate exists, keep the highest raster_value and merge species
                routePoints[existingPointIndex].raster_value = Math.max(
                  routePoints[existingPointIndex].raster_value,
                  row.raster_value
                );
                //merge species arrays
                if(row.raster_value > 0.3 && row.species && row.species.length > 0){
                    routePoints[existingPointIndex].species = [...new Set([...routePoints[existingPointIndex].species,...row.species])];
                }

              } else {
                // Otherwise, add a new unique point
                routePoints.push({
                  lat,
                  lon,
                  raster_value: row.raster_value,
                  species: row.raster_value > 0.3 && row.species && row.species.length > 0 ? row.species : []
                });
              }
            });
          };

          if (index === 0) {
            if (startDistanceToLast < startDistanceToFirst) {
              processCoordinates(coordinates.slice().reverse());
            } else {
              processCoordinates(coordinates);
            }
          } else {
            const lastPointInRoute = routePoints[routePoints.length - 1];

            const distanceToFirst = calculateDistance(
              lastPointInRoute.lat,
              lastPointInRoute.lon,
              firstCoord[1],
              firstCoord[0]
            );
            const distanceToLast = calculateDistance(
              lastPointInRoute.lat,
              lastPointInRoute.lon,
              lastCoord[1],
              lastCoord[0]
            );

            if (distanceToLast < distanceToFirst) {
              processCoordinates(coordinates.slice().reverse());
            } else {
              processCoordinates(coordinates);
            }
          }
        }
      });

      // Format the distance
      const formattedDistance =
        totalDistance < 1000
          ? `${totalDistance.toFixed(0)} meters`
          : `${(totalDistance / 1000).toFixed(2)} km`;

      console.log("formattedDistance,", formattedDistance);

      // Format the time
      const totalHours = Math.floor(totalTime);
      const totalMinutes = Math.round((totalTime - totalHours) * 60);
      const formattedTime =
        totalHours > 0
          ? `${totalHours}h ${totalMinutes}min`
          : `${totalMinutes} min`;

      console.log("formattedTime,", formattedTime);

      // Store route data for comparison
      allRoutes[key] = routePoints;

      console.log(routePoints)

      // Store results in responseData, including hasRisk
      responseData[key] = {
        route: routePoints,
        distance: formattedDistance,
        time: formattedTime,
        hasRisk, // Added risk flag
      };
    }

    // Check if all routes are identical
    const routeKeys = Object.keys(allRoutes);
    if (
      routeKeys.length > 1 &&
      JSON.stringify(allRoutes[routeKeys[0]]) === JSON.stringify(allRoutes[routeKeys[1]])
    ) {
      console.log("Duplicate routes detected, returning only the default route.");
      responseData = { default: responseData[routeKeys[0]] }; // Keep only the first route
    }

    res.status(200).json(responseData);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});


// Test if we can get the raster_values for a single point
app.post("/raster", async (req, res) => {
  const {point} = req.body;

  try {
    const response = await getRasterValue(point);
    res.status(200).json(response);
  } catch (err) {
    console.error("Error fetching search results:", err);
    res.status(500).json({ error: "Internal server error" });
  }
})


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
app.listen(3000, () => {
  console.log("Server started on port 3000");
});
