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
    console.log("inside the getRoute");
    const startNode = await pool.query(`
      SELECT id, ST_Distance(the_geom::geography, ST_SetSRID(ST_Point(${start.lon}, ${start.lat}), 4326)::geography) AS dist
      FROM ways_vertices_pgr
      ORDER BY dist ASC
      LIMIT 1;
    `);
    // 38.902464, -9.163266
    // 1596063

    const endNode = await pool.query(`
      SELECT id, ST_Distance(the_geom::geography, ST_SetSRID(ST_Point(${end.lon}, ${end.lat}), 4326)::geography) AS dist
      FROM ways_vertices_pgr
      ORDER BY dist ASC
      LIMIT 1;
    `);

    // 38.902290, -9.177862
    // 1696467

    const route = await pool.query(`
      SELECT *,
      ST_AsGeoJSON(geom) AS geojson
      FROM pgr_dijkstra(
        'SELECT gid AS id, source, target, length_m as cost FROM ways',
        ${startNode.rows[0].id}, ${endNode.rows[0].id},
        directed := false
      ) AS route
      JOIN ways ON route.edge = ways.gid;
    `);
    

    return route.rows;
  } catch (err) {
    console.error(err);
  }
};

// Example usage with Coruña to Chantada:
// getRoute({ lon: -7.863333, lat: 42.336388 }, { lon: -7.77115, lat: 42.60876 })
//   .then((route) => console.log(route))
//   .catch((err) => console.error(err))

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
    // console.log("inside the /route post");
    const { start, end } = req.body;
    // console.log("start", start);
    // console.log("end", end);

    const route = await getRoute(start, end);
    if (!route) {
      return res.status(404).json({ error: "Route not found" });
    }

    console.log("route", route);

    const routePoints = route.map((row) => {
      
      const geojson = row.geojson; // Parse the GeoJSON string
      console.log("geojson", geojson);
      const coordinates = geojson.coordinates;
      console.log("coordinates", coordinates);
    
      // Flatten the coordinates into lat and lon
      return coordinates.map((coord) => ({
        lat: coord[1],  // The second element is latitude
        lon: coord[0],  // The first element is longitude
      }));
    }).flat(); // Use flat() to merge all the arrays into a single list of points
    
    // Send the response with the flattened route points
    res.status(200).json({ route: routePoints });

  } catch (err) {
    console.error(err);
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
