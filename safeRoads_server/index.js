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

const pool2 = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME2,
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

const getRasterValue = async (start) => {
  try{
    const rasterValue = await pool.query(`
      SELECT ST_VALUE(rast,1,ST_SetSRID(ST_MakePoint(${start.lon}, ${start.lat}), 4326)) AS raster_value
      FROM public.raster_table
      WHERE ST_Intersects(rast,ST_SetSRID(ST_MakePoint(${start.lon}, ${start.lat}), 4326));
    `)
    // 41.84083,-7.89093 // Test with an higher value
    const result = rasterValue;
    // console.log(result); 
    const value = rasterValue.rows[0]?.raster_value;
    // console.log(value); 
    return value;
  } catch (err){
    console.error(err);
  }
};

// Route computation function
const getRoute = async (start, end) => {
  try {
    // Get start and end nodes
    const startNodeQuery = `
      SELECT id, ST_Distance(the_geom::geography, ST_SetSRID(ST_Point(${start.lon}, ${start.lat}), 4326)::geography) AS dist
      FROM ways_vertices_pgr
      ORDER BY dist ASC
      LIMIT 1;
    `;
    const startNode = await pool.query(startNodeQuery);
    console.log("startNode: ", startNode);

    const endNodeQuery = `
      SELECT id, ST_Distance(the_geom::geography, ST_SetSRID(ST_Point(${end.lon}, ${end.lat}), 4326)::geography) AS dist
      FROM ways_vertices_pgr
      ORDER BY dist ASC
      LIMIT 1;
    `;
    const endNode = await pool.query(endNodeQuery);
    console.log("endNode: ", endNode);

    // Calculate bounding box
    const bufferDistance = 0.05; // ~5km buffer
    const minLat = Math.min(start.lat, end.lat) - bufferDistance;
    const maxLat = Math.max(start.lat, end.lat) + bufferDistance;
    const minLon = Math.min(start.lon, end.lon) - bufferDistance;
    const maxLon = Math.max(start.lon, end.lon) + bufferDistance;

    // Step 1: Create a temporary table with geometries within the bounding box
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
        raster_value DOUBLE PRECISION DEFAULT NULL
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

    // Step 2: Add raster values to the temp table
    const updateTempTableWithRasterQuery = `
      UPDATE temp_ways
      SET raster_value = subquery.raster_value
      FROM (
        SELECT w_inner.gid,
              AVG(COALESCE(ST_Value(
                r.rast, 
                1, 
                ST_SetSRID(ST_MakePoint(
                  ST_X(ST_Centroid(w_inner.the_geom)), 
                  ST_Y(ST_Centroid(w_inner.the_geom))
                ), 4326)
              ), 1)) AS raster_value
        FROM temp_ways w_inner
        LEFT JOIN raster_table r 
          ON ST_Intersects(
              r.rast, 
              w_inner.the_geom -- Geometry from temp_ways
            )
        GROUP BY w_inner.gid
      ) AS subquery
      WHERE temp_ways.gid = subquery.gid;
    `;
    await pool.query(updateTempTableWithRasterQuery);
    console.log("Raster values added to the temporary table.");

    // const routeBefore = `
    //   SELECT *,
    //   ST_AsGeoJSON(the_geom) AS geojson,
    //   maxspeed_forward,
    //   maxspeed_backward
    //   FROM pgr_dijkstra(
    //     'SELECT gid AS id, source, target, cost, reverse_cost, maxspeed_forward, maxspeed_backward FROM ways',
    //     ${startNode.rows[0].id}, ${endNode.rows[0].id},
    //     directed := true
    //   ) AS route
    //   JOIN ways ON route.edge = ways.gid;
    //   `;

    // Step 3: Run the pgr_dijkstra query on the temp table
    const routeQuery = `
      SELECT *,
             ST_AsGeoJSON(the_geom) AS geojson,
             maxspeed_forward,
             maxspeed_backward
      FROM pgr_dijkstra(
        'SELECT gid AS id, 
                source, 
                target,
                cost * 
                  CASE
                    WHEN raster_value = 1 THEN 1.1
                    WHEN raster_value = 2 THEN 1.2
                    WHEN raster_value = 3 THEN 1.5
                    WHEN raster_value = 4 THEN 2
                    WHEN raster_value = 5 THEN 3
                    WHEN raster_value = 6 THEN 5
                    ELSE 1
                  END AS cost,
                reverse_cost * 
                  CASE
                    WHEN raster_value = 1 THEN 1.1
                    WHEN raster_value = 2 THEN 1.2
                    WHEN raster_value = 3 THEN 1.5
                    WHEN raster_value = 4 THEN 2
                    WHEN raster_value = 5 THEN 3
                    WHEN raster_value = 6 THEN 5
                    ELSE 1
                  END AS reverse_cost
         FROM temp_ways',
        ${startNode.rows[0].id}, 
        ${endNode.rows[0].id},
        directed := true
      ) AS route
      JOIN temp_ways ON route.edge = temp_ways.gid
      ORDER BY route.seq; -- Ensure the results are ordered by seq
    `;
    const route = await pool.query(routeQuery);
    console.log(route.rows);

    // Step 4: Clean up the temporary table
    await pool.query("DROP TABLE IF EXISTS temp_ways;");
    console.log("Temporary table dropped.");

    return route.rows;
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
app.use('/tiles', express.static(path.join(__dirname, 'tiles')));

app.post("/send", (req, res) => {
  // Timeout de 5 segundos para testar
  setTimeout( function () {
    const receivedToken = req.body.fcmToken;
    const receivedtitle = req.body.title;
    const receivedbody = req.body.body;

    const message = {
      token: receivedToken,
      notification: {
        body: receivedbody,
        title: receivedtitle,
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
        console.log("Successfully sent message:", response);
      })
      .catch((error) => {
        res.status(400).json({ error: error.message });
        console.log("Error sending message:", error);
      });
    }, 5000
  )
});

app.post("/route", async (req, res) => {
  try {
    const { start, end } = req.body;
    const route = await getRoute(start, end);

    if (!route || route.length === 0) {
      return res.status(404).json({ error: "Route not found" });
    }

    let routePoints = [];
    let totalDistance = 0; // in meters
    let totalTime = 0; // in hours

    route.forEach((row, index) => {
      const geojson = JSON.parse(row.geojson); // Parse the GeoJSON
      const segmentDistance = parseFloat(row.length_m); // Distance in meters

      // Determine the speed to use based on direction
      const speed =
        row.reverse_cost === -1
          ? row.maxspeed_forward // If reverse_cost is -1, use forward speed
          : row.maxspeed_backward;

      if (!speed || speed <= 0) {
        console.warn("Invalid speed value for segment, skipping:", row);
        return; // Skip segments with invalid speed
      }

      // Convert speed to m/s and calculate time for this segment
      const speedMps = (speed * 1000) / 3600; // Convert km/h to m/s
      const segmentTime = segmentDistance / speedMps; // Time in seconds
      totalTime += segmentTime / 3600; // Convert to hours and accumulate
      totalDistance += segmentDistance; // Accumulate distance

      if (geojson.type === "LineString") {
        const coordinates = geojson.coordinates;
        const firstCoord = coordinates[0];
        const lastCoord = coordinates[coordinates.length - 1];

        if (index === 0) {
          // First set of coordinates, determine the best orientation
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

          if (startDistanceToLast < startDistanceToFirst) {
            routePoints.push(
              ...coordinates.reverse().map(([lon, lat]) => ({ lat, lon, raster_value: row.raster_value }))
            );
          } else {
            routePoints.push(...coordinates.map(([lon, lat]) => ({ lat, lon, raster_value: row.raster_value })));
          }
        } else {
          // For subsequent sets of coordinates
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
            routePoints.push(
              ...coordinates.reverse().map(([lon, lat]) => ({ lat, lon, raster_value: row.raster_value }))
            );
          } else {
            routePoints.push(...coordinates.map(([lon, lat]) => ({ lat, lon, raster_value: row.raster_value })));
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


    res.status(200).json({
      route: routePoints,
      distance: formattedDistance,
      time: formattedTime,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});


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

app.get("/search", async (req, res) => {
  const { query, limit = 5, lang = 'en' } = req.query;
  console.log("query:", query)

  if (!query) {
    return res.status(400).json({ error: "Query parameter is required" });
  }

  try {
    const response = await fetch(`https://photon.komoot.io/api/?q=${encodeURIComponent(query)},portugal&limit=${limit}&lang=${lang}`); //Added Portugal to restrict the options
    const data = await response.json();
    // console.log(data.features[0]);
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
