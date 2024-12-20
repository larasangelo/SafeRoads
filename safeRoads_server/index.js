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

// Route computation function
const getRoute = async (start, end) => {
  try {
    // console.log("inside the getRoute");
    const startNode = await pool.query(`
      SELECT id, ST_Distance(the_geom::geography, ST_SetSRID(ST_Point(${start.lon}, ${start.lat}), 4326)::geography) AS dist
      FROM ways_vertices_pgr
      ORDER BY dist ASC
      LIMIT 1;
    `);
    // 38.902464, -9.163266
    // 1596063
    console.log("startNode: ", startNode);

    const endNode = await pool.query(`
      SELECT id, ST_Distance(the_geom::geography, ST_SetSRID(ST_Point(${end.lon}, ${end.lat}), 4326)::geography) AS dist
      FROM ways_vertices_pgr
      ORDER BY dist ASC
      LIMIT 1;
    `);

    // 38.902290, -9.177862
    // 1696467
    console.log("endNode: ", endNode);

    const route = await pool.query(`
      SELECT *,
      ST_AsGeoJSON(the_geom) AS geojson
      FROM pgr_dijkstra(
        'SELECT gid AS id, source, target, cost, reverse_cost FROM ways',
        ${startNode.rows[0].id}, ${endNode.rows[0].id},
        directed := true
      ) AS route
      JOIN ways ON route.edge = ways.gid;
    `);
    
    console.log(route.rows)
    return route.rows;
  } catch (err) {
    console.error(err);
  }
};

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

app.post("/send", (req, res) => {
  const receivedToken = req.body.fcmToken;

  const message = {
    notification: {
      title: "Destination Set",
      body: "You have set a new destination!",
    },
    token: receivedToken,
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
});

app.post("/route", async (req, res) => {
  try {
    const { start, end } = req.body;
    const route = await getRoute(start, end);
    if (!route) {
      return res.status(404).json({ error: "Route not found" });
    }

    let routePoints = [];

    route.forEach((row, index) => {
      const geojson = JSON.parse(row.geojson); // Parse the GeoJSON
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
            // If last coordinate is closer to start, reverse the segment
            routePoints.push(
              ...coordinates.reverse().map(([lon, lat]) => ({ lat, lon }))
            );
          } else {
            // Otherwise, add normally
            routePoints.push(...coordinates.map(([lon, lat]) => ({ lat, lon })));
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
            // If the last coordinate is closer, reverse the order
            routePoints.push(
              ...coordinates.reverse().map(([lon, lat]) => ({ lat, lon }))
            );
          } else {
            // Otherwise, add normally
            routePoints.push(...coordinates.map(([lon, lat]) => ({ lat, lon })));
          }
        }
      }
    });

    // console.log("routePoints:", routePoints);
    res.status(200).json({ route: routePoints });
  } catch (err) {
    console.error(err);
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
