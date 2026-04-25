// src/repositories/users.js — v6.0.0
const bcrypt = require('bcryptjs');
const { query, one, many } = require('../config/db');
const { mapUser, mapUserWithPassword } = require('../db/mappers');

async function findById(id) {
  const row = await one('SELECT * FROM users WHERE id = $1', [id]);
  return mapUser(row);
}

async function findByIdWithPassword(id) {
  const row = await one('SELECT * FROM users WHERE id = $1', [id]);
  return mapUserWithPassword(row);
}

async function findByEmail(email) {
  const row = await one('SELECT * FROM users WHERE email = $1', [email]);
  return mapUserWithPassword(row);
}

async function existsByEmail(email, exceptId = null) {
  if (exceptId) {
    const row = await one(
      'SELECT 1 FROM users WHERE email = $1 AND id <> $2',
      [email, exceptId],
    );
    return !!row;
  }
  const row = await one('SELECT 1 FROM users WHERE email = $1', [email]);
  return !!row;
}

async function listAll() {
  const rows = await many('SELECT * FROM users ORDER BY created_at DESC');
  return rows.map(mapUser);
}

async function listOnline() {
  const rows = await many('SELECT * FROM users WHERE is_online = true');
  return rows.map(mapUser);
}

async function create({ name, email, password, role }) {
  const hash = await bcrypt.hash(password, 10);
  const row = await one(
    `INSERT INTO users (name, email, password, role)
       VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [name, email, hash, role],
  );
  return mapUser(row);
}

async function updateById(id, { name, email, password, role }) {
  const sets = [];
  const vals = [];
  let n = 1;
  if (name !== undefined) { sets.push(`name = $${n++}`); vals.push(name); }
  if (email !== undefined) { sets.push(`email = $${n++}`); vals.push(email); }
  if (role !== undefined) { sets.push(`role = $${n++}`); vals.push(role); }
  if (password !== undefined) {
    const hash = await bcrypt.hash(password, 10);
    sets.push(`password = $${n++}`);
    vals.push(hash);
  }
  if (!sets.length) return findById(id);
  vals.push(id);
  const row = await one(
    `UPDATE users SET ${sets.join(', ')} WHERE id = $${n} RETURNING *`,
    vals,
  );
  return mapUser(row);
}

async function deleteById(id) {
  const { rowCount } = await query('DELETE FROM users WHERE id = $1', [id]);
  return rowCount > 0;
}

async function setLoginState(id, { isOnline, lastLogin = null }) {
  const sets = ['is_online = $1'];
  const vals = [isOnline];
  let n = 2;
  if (lastLogin) {
    sets.push(`last_login = $${n++}`);
    vals.push(lastLogin);
  }
  vals.push(id);
  await query(
    `UPDATE users SET ${sets.join(', ')} WHERE id = $${n}`,
    vals,
  );
}

module.exports = {
  findById,
  findByIdWithPassword,
  findByEmail,
  existsByEmail,
  listAll,
  listOnline,
  create,
  updateById,
  deleteById,
  setLoginState,
};
