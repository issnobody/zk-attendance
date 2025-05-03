import express from "express";
import fs from "fs";
import { groth16 } from "snarkjs";

const vKey = JSON.parse(fs.readFileSync("verification_key.json"));
const app  = express();
app.use(express.json({ limit: "1mb" }));

app.post("/verify", async (req, res) => {
  const { publicSignals, proof } = req.body;
  const ok = await groth16.verify(vKey, publicSignals, proof);
  res.json({ ok });
  console.log("Proof:", ok ? "✅" : "❌");
});

app.listen(5000, () => console.log("Verifier 🔥  http://localhost:5000"));

