// verifier.js

import express from 'express'
import fs from 'fs'
import { groth16 } from 'snarkjs'

const app = express()
app.use(express.json({ limit: "2mb" }))

// Pre-load everything
const vKey     = JSON.parse(fs.readFileSync(new URL('./verification_key.json', import.meta.url)))
const wasm     = fs.readFileSync(new URL('./proximity.wasm',             import.meta.url))
const zkey     = fs.readFileSync(new URL('./proximity_final.zkey',       import.meta.url))

app.post('/prove', async (req, res) => {
  try {
    const { nonceHex } = req.body;
    if (typeof nonceHex !== 'string' || nonceHex.length !== 16) {
      return res.status(400).json({ error: 'nonceHex must be 16 hex chars' });
    }

    // Split into two 8-hex-char substrings
    const hex0 = nonceHex.slice(0, 8);   // first 4 bytes
    const hex1 = nonceHex.slice(8, 16);  // next 4 bytes

    // Convert each to a decimal string
    const a0 = BigInt('0x' + hex0).toString();
    const a1 = BigInt('0x' + hex1).toString();

    // Build the 2-element array
    const input = { nonce: [ a0, a1 ] };

    const { proof, publicSignals } =
      await groth16.fullProve(input, wasm, zkey);

    console.log('✔️ /prove success:', publicSignals);
    return res.json({ proof, publicSignals });
  } catch (e) {
    console.error('❌ /prove error', e);
    return res.status(500).json({ error: e.toString() });
  }
});

app.post('/verify', async (req, res) => {
  try {
    const { proof, publicSignals } = req.body
    const ok = await groth16.verify(vKey, publicSignals, proof)
    console.log('→ proof verified =', ok)
    return res.json({ verified: ok })
  } catch (e) {
    console.error('❌ verify error:', e)
    return res.json({ verified: false })
  }
})

const PORT = 5100
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Verifier 🔥 listening on port ${PORT}`)
})

