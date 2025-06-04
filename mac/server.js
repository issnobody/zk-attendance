// server.js

import express from 'express';
import bodyParser from 'body-parser';
import fs from 'fs-extra';
import path from 'path';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { groth16 } from 'snarkjs';
import mongoose from 'mongoose'

const JWT_SECRET = process.env.JWT_SECRET || 'change_this_to_strong_secret'
const MONGO_URI  = process.env.MONGO_URI  || 'mongodb://127.0.0.1:27017/zk_attendance'
const PORT       = process.env.PORT       || 5100

// — load your circom/verification key —
const vKey = JSON.parse(
  fs.readFileSync(new URL('./verification_key.json', import.meta.url))
)

// ─── Mongoose schemas ───────────────────────────────
await mongoose.connect(MONGO_URI, { useNewUrlParser: true, useUnifiedTopology: true })

const userSchema = new mongoose.Schema({
  username:     { type: String, unique: true, required: true },
  passwordHash: String,
  role:         { type: String, enum: ["user","admin"], default: "user" }
});

const User = mongoose.model('User', userSchema)

const attendanceSchema = new mongoose.Schema({
  user:      { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  timestamp: { type: Date, default: Date.now },
  status:    { type: String, required: true }
})
const Attendance = mongoose.model('Attendance', attendanceSchema)

// ─── Express setup ──────────────────────────────────
const app = express()
app.use(express.json({ limit: '1mb' }))

// server.js

function authenticate(req, res, next) {
  const auth = req.headers.authorization?.split(' ');
  if (auth?.[0] === 'Bearer' && auth[1]) {
    try {
      const payload = jwt.verify(auth[1], JWT_SECRET);
      req.user = payload;   // { id, username, role }
      return next();
    } catch {}
  }
  res.status(401).json({ error: 'Unauthorized' });
}

function requireAdmin(req, res, next) {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Forbidden: admin only' });
  }
  next();
}


// ─── Health check ──────────────────────────────────
app.get('/ping', (_req, res) => res.send('pong'))

// ─── Sign up ───────────────────────────────────────
app.post('/signup', async (req, res) => {
  const { username, password } = req.body
  if (!username || !password) {
    return res.status(400).json({ error: 'username+password required' })
  }
  const hash = await bcrypt.hash(password, 10)
  try {
    const user = new User({ username, passwordHash: hash })
    await user.save()
    res.json({ success: true })
  } catch (e) {
    res.status(400).json({ error: 'username taken' })
  }
})

// ─── Log in ────────────────────────────────────────
app.post('/login', async (req, res) => {
  const { username, password } = req.body
  const user = await User.findOne({ username })
  if (!user || !await bcrypt.compare(password, user.passwordHash)) {
    return res.status(401).json({ error: 'Invalid credentials' })
  }
  const token = jwt.sign(
    { id: user._id, username: user.username, role: user.role },
    JWT_SECRET,
    { expiresIn: '12h' }
  )
  res.json({ token })
})

// ─── Record attendance ─────────────────────────────
app.post('/attendance', authenticate, async (req, res) => {
  const { status } = req.body
  const rec = new Attendance({
    user: req.user.id,
    status
  })
  await rec.save()
  res.json({ success: true })
})

// ─── Fetch attendance history ──────────────────────
app.get('/attendance', authenticate, async (req, res) => {
  const history = await Attendance
    .find({ user: req.user.id })
    .sort({ timestamp: -1 })
    .populate('user', 'username')     //
    .lean()
  // map to { date, status }
  res.json(history.map(r => ({
    date: r.timestamp,
    status: r.status,
    user:   r.user.username

  })))
})

// ← Generate proof
app.post('/prove', async (req, res) => {
  try {
    const { nonceHex } = req.body;
    // convert hex → two field elements
    const a = BigInt('0x' + nonceHex.slice(0,16));
    const b = BigInt('0x' + nonceHex.slice(16));
    const input = { nonce: [a.toString(), b.toString()] };

    const { proof, publicSignals } =
      await groth16.fullProve(
        input,
        'proximity.wasm',
        'proximity_final.zkey'
      );
    return res.json({ proof, publicSignals });
  } catch (e) {
    console.error('❌ /prove error', e);
    return res.status(500).json({ error: e.toString() });
  }
});

app.post('/verify', async (req, res) => {
  const { proof, publicSignals } = req.body
  try {
    const ok = await groth16.verify(vKey, publicSignals, proof)
    console.log('→ proof verified =', ok)
    res.json({ verified: ok })
  } catch (e) {
    console.error('❌ verify error:', e)
    res.status(500).json({ error: e.toString() })
  }
})

app.get('/users', authenticate, async (req, res) => {
  const list = await User
    .find({ role: 'user' })
    .select('username')     // we only need the username and _id
    .lean();

  // map to your AdminUser shape:
  res.json(
    list.map(u => ({
      id:       u._id.toString(),
      username: u.username
    }))
  );
});

// ─── Get attendance for any user ───────────────────
// Fetch attendance history for *any* user (admin only)
app.get(
  '/users/:id/attendance',
  authenticate,            // must be logged in as admin
  async (req, res) => {
    try {
      const history = await Attendance
        .find({ user: req.params.id })
        .sort({ timestamp: -1 })
        .lean();
      return res.json(
        history.map(r => ({
          id:        r._id.toString(),
          date:      r.timestamp,
          status:    r.status
        }))
      );
    } catch (e) {
      console.error('❌ /users/:id/attendance', e);
      return res.status(500).json({ error: e.toString() });
    }
  }
);

app.get('/me', authenticate, (req,res) => {
  res.json({
    id:       req.user.id,
    username: req.user.username,
    role:     req.user.role
  });
});


// ─── Start server ──────────────────────────────────
app.listen(PORT, () => {
  console.log(`Server listening on http://0.0.0.0:${PORT}`)
})

