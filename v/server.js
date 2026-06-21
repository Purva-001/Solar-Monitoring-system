const express = require("express");
const multer = require("multer");
const cors = require("cors");
const fs = require("fs");
const path = require("path");

const app = express();
app.use(cors());

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, "uploads/");
    },
    filename: (req, file, cb) => {
        cb(null, Date.now() + ".jpg");
    }
});

const upload = multer({ storage });

// 📤 Upload route
app.post("/upload", upload.single("file"), (req, res) => {
    console.log("Image received:", req.file.filename);
    res.json({ message: "Upload success", file: req.file.filename });
});

// 📸 Get latest image
app.get("/uploads/latest.jpg", (req, res) => {
    try {
        const dir = path.join(__dirname, "uploads");
        const files = fs
            .readdirSync(dir)
            .filter((f) => f.toLowerCase().endsWith(".jpg"))
            .map((f) => ({
                name: f,
                mtimeMs: fs.statSync(path.join(dir, f)).mtimeMs,
            }))
            .sort((a, b) => b.mtimeMs - a.mtimeMs);

        if (!files.length) {
            return res.status(404).send("No images found");
        }

        return res.sendFile(path.join(dir, files[0].name));
    } catch (e) {
        return res.status(500).send("Failed to load latest image");
    }
});
app.use("/uploads", express.static("uploads"));

app.listen(3001, "0.0.0.0", () => {
    console.log("Server running on 10.235.197.223:3001");
});