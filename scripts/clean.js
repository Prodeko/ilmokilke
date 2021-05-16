#!/usr/bin/env node
try {
  const rimraf = require("rimraf")

  rimraf.sync(`${__dirname}/../@app/*/dist`)
  rimraf.sync(`${__dirname}/../@app/*/tsconfig.tsbuildinfo`)
  rimraf.sync(`${__dirname}/../@app/client/.next`)
  rimraf.sync(`${__dirname}/../@app/server/uploads/*`)
} catch (e) {
  console.error("Failed to clean up, perhaps rimraf isn't installed?")
  console.error(e)
}
