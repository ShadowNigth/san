#!/usr/bin/env node
/**
 * Importador de assets adicionales desde https://github.com/3kh0/cs2go.git para Godot 4.
 *
 * El repositorio incluido mantiene Dust II, armas principales, granadas, C4, bayoneta,
 * agentes base y audio completo por debajo del límite de 128 MB. Ejecuta este script
 * localmente para descargar e importar todas las armas restantes, cuchillos adicionales,
 * mapas extra (Mirage, Inferno, Nuke, Ancient, Anubis, Overpass, Vertigo, Train),
 * skins/agentes extra y music kits convirtiendo automáticamente cualquier GLB con
 * EXT_meshopt_compression o KHR_mesh_quantization a GLB estándar compatible con Godot 4.
 *
 * Uso:
 *   npm install --no-save @gltf-transform/core @gltf-transform/extensions @gltf-transform/functions meshoptimizer
 *   node scripts/import_cs2go_assets.mjs [--source=/ruta/a/cs2go] [--maps] [--weapons] [--agents] [--music] [--all]
 */

import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { execFileSync } from "node:child_process";
import { NodeIO } from "@gltf-transform/core";
import { KHRONOS_EXTENSIONS, EXTTextureWebP, EXTMeshoptCompression } from "@gltf-transform/extensions";
import { dequantize, simplify, weld, dedup, prune } from "@gltf-transform/functions";
import { MeshoptDecoder, MeshoptSimplifier } from "meshoptimizer";

function parseArgs(argv) {
  const opts = { source: "", maps: false, weapons: false, agents: false, music: false };
  for (const a of argv) {
    if (a.startsWith("--source=")) opts.source = a.slice(9);
    else if (a === "--maps") opts.maps = true;
    else if (a === "--weapons") opts.weapons = true;
    else if (a === "--agents") opts.agents = true;
    else if (a === "--music") opts.music = true;
    else if (a === "--all") opts.maps = opts.weapons = opts.agents = opts.music = true;
  }
  if (!opts.maps && !opts.weapons && !opts.agents && !opts.music) {
    opts.weapons = true;
  }
  return opts;
}

async function createIO() {
  await MeshoptDecoder.ready;
  await MeshoptSimplifier.ready;
  return new NodeIO()
    .registerExtensions([...KHRONOS_EXTENSIONS, EXTTextureWebP, EXTMeshoptCompression])
    .registerDependencies({ "meshopt.decoder": MeshoptDecoder });
}

function bakeWorldTransforms(doc) {
  for (const n of doc.getRoot().listNodes()) {
    const mesh = n.getMesh();
    if (!mesh) continue;
    const mat = n.getWorldMatrix();
    for (const p of mesh.listPrimitives()) {
      const pos = p.getAttribute("POSITION");
      if (!pos) continue;
      const arr = pos.getArray();
      const out = new Float32Array(arr.length);
      for (let i = 0; i < arr.length; i += 3) {
        out[i] = mat[0] * arr[i] + mat[4] * arr[i + 1] + mat[8] * arr[i + 2] + mat[12];
        out[i + 1] = mat[1] * arr[i] + mat[5] * arr[i + 1] + mat[9] * arr[i + 2] + mat[13];
        out[i + 2] = mat[2] * arr[i] + mat[6] * arr[i + 1] + mat[10] * arr[i + 2] + mat[14];
      }
      pos.setArray(out);
    }
  }
  for (const n of doc.getRoot().listNodes()) {
    n.setTranslation([0, 0, 0]);
    n.setRotation([0, 0, 0, 1]);
    n.setScale([1, 1, 1]);
  }
}

async function convertGlb(io, srcPath, dstPath, options = {}) {
  let bytes = fs.readFileSync(srcPath);
  if (srcPath.endsWith(".gz")) bytes = zlib.gunzipSync(bytes);
  const doc = await io.readBinary(new Uint8Array(bytes));
  await doc.transform(dequantize(), dedup(), prune());
  for (const ext of doc.getRoot().listExtensionsUsed()) {
    if (ext.extensionName === "EXT_meshopt_compression") ext.dispose();
  }
  if (options.bakeTransforms) {
    bakeWorldTransforms(doc);
  }
  if (options.simplifyRatio && options.simplifyRatio < 1.0) {
    await doc.transform(
      weld({ tolerance: options.weldTolerance ?? 0.0002 }),
      simplify({
        simplifier: MeshoptSimplifier,
        ratio: options.simplifyRatio,
        error: options.error ?? 0.006,
        lockBorder: false,
      })
    );
  }
  fs.mkdirSync(path.dirname(dstPath), { recursive: true });
  fs.writeFileSync(dstPath, await io.writeBinary(doc));
  console.log(`Exportado: ${path.relative(process.cwd(), dstPath)}`);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  let srcRoot = opts.source;
  if (!srcRoot) {
    const tmpDir = "/tmp/cs2go_import_src";
    if (!fs.existsSync(tmpDir)) {
      console.log("Clonando sparse checkout de https://github.com/3kh0/cs2go.git en", tmpDir);
      execFileSync(
        "git",
        ["clone", "--depth", "1", "--filter=blob:none", "--sparse", "https://github.com/3kh0/cs2go.git", tmpDir],
        { stdio: "inherit" }
      );
    }
    const checkouts = [];
    if (opts.weapons) {
      checkouts.push(
        "packages/assets/public/models/viewmodels",
        "packages/assets/public/models/karambit.glb",
        "packages/assets/public/models/butterfly.glb"
      );
    }
    if (opts.maps) checkouts.push("packages/assets/public/models/maps");
    if (opts.agents) checkouts.push("packages/assets/public/models/agents");
    if (opts.music) checkouts.push("packages/assets/public/audio/music-kits");
    if (checkouts.length > 0) {
      execFileSync("git", ["-C", tmpDir, "sparse-checkout", "set", "--no-cone", ...checkouts], {
        stdio: "inherit",
      });
    }
    srcRoot = tmpDir;
  }

  const pubDir = path.join(srcRoot, "packages/assets/public");
  const io = await createIO();

  if (opts.weapons) {
    const vmDir = path.join(pubDir, "models/viewmodels");
    if (fs.existsSync(vmDir)) {
      for (const file of fs.readdirSync(vmDir)) {
        if (!file.endsWith("-hd.glb")) continue;
        const slug = file.replace(/-hd\.glb$/, "");
        await convertGlb(
          io,
          path.join(vmDir, file),
          path.resolve("assets/models/viewmodels", `${slug}.glb`),
          { simplifyRatio: 0.35, error: 0.006 }
        );
      }
    }
    for (const k of ["karambit.glb", "butterfly.glb"]) {
      const kp = path.join(pubDir, "models", k);
      if (fs.existsSync(kp)) await convertGlb(io, kp, path.resolve("assets/models", k));
    }
  }

  if (opts.maps) {
    const mapsDir = path.join(pubDir, "models/maps");
    if (fs.existsSync(mapsDir)) {
      for (const f of fs.readdirSync(mapsDir)) {
        if (f.endsWith(".glb.gz") || f.endsWith(".glb")) {
          const outName = f.replace(/\.gz$/, "").replace(/-/g, "_");
          const isPhys = outName.includes("physics");
          await convertGlb(io, path.join(mapsDir, f), path.resolve("assets/models/maps", outName), {
            bakeTransforms: isPhys,
          });
        } else if (f.endsWith(".hdr") || f.endsWith(".png") || f.endsWith(".json")) {
          fs.copyFileSync(path.join(mapsDir, f), path.resolve("assets/models/maps", f));
        }
      }
    }
  }

  if (opts.agents) {
    const agentsDir = path.join(pubDir, "models/agents/roster");
    if (fs.existsSync(agentsDir)) {
      for (const f of fs.readdirSync(agentsDir)) {
        if (f.endsWith(".glb")) {
          await convertGlb(io, path.join(agentsDir, f), path.resolve("assets/models/agents", f));
        }
      }
    }
  }

  if (opts.music) {
    const mkDir = path.join(pubDir, "audio/music-kits");
    if (fs.existsSync(mkDir)) {
      fs.cpSync(mkDir, path.resolve("assets/audio/music-kits"), { recursive: true });
      console.log("Music kits copiados a assets/audio/music-kits");
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
