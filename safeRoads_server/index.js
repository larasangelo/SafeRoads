import admin from "firebase-admin";
import { readFileSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { getMessaging } from 'firebase-admin/messaging';
import express from 'express';
import cors from 'cors';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load the service account JSON
const serviceAccount = JSON.parse(
  readFileSync(path.join(__dirname, "flutter-saferoads-firebase-adminsdk-sekrk-712d669273.json"), "utf8")
);

// Initialize Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'flutter-saferoads',
});

const app = express();
app.use(express.json());
app.use(cors({ origin: '*' }));

app.post('/send', (req, res) => {
  const receivedToken = req.body.fcmToken;
  // console.log("receivedToken: ", receivedToken)

  const message = {
    notification: {
      title: 'Destination Set',
      body: 'You have set a new destination!',
    },
    token: receivedToken,
  };

  getMessaging()
    .send(message)
    .then((response) => {
      res.status(200).json({
        message: 'Successfully sent message',
        token: receivedToken,
      });
      console.log('Successfully sent message:', response);
    //   console.log('receivedToken:', receivedToken);

    })
    .catch((error) => {
      res.status(400).json({ error: error.message });
      console.log('Error sending message:', error);
    });
});

app.listen(3000, () => {
  console.log('Server started on port 3000');
});
