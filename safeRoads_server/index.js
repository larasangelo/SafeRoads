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
      ST_AsGeoJSON(the_geom) AS geojson,
      maxspeed_forward,
      maxspeed_backward
      FROM pgr_dijkstra(
        'SELECT gid AS id, source, target, cost, reverse_cost, maxspeed_forward, maxspeed_backward FROM ways',
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
              ...coordinates.reverse().map(([lon, lat]) => ({ lat, lon }))
            );
          } else {
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
            routePoints.push(
              ...coordinates.reverse().map(([lon, lat]) => ({ lat, lon }))
            );
          } else {
            routePoints.push(...coordinates.map(([lon, lat]) => ({ lat, lon })));
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
