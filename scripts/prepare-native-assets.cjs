// Offline build-time conversion. The iOS app ships only native Metal assets.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'web/assets');
const output = path.join(root, 'NativeAssets');
const word = n => { const b = Buffer.alloc(4); b.writeUInt32LE(n); return b; };

async function main() {
  fs.mkdirSync(output, { recursive: true });
  const draco = await require(path.join(source, 'draco_wasm_wrapper-fZCQGLGb.js'))({
    wasmBinary: fs.readFileSync(path.join(source, 'draco_decoder-Z1_iN-Ht.wasm'))
  });
  const glb = fs.readFileSync(path.join(source, 'raspberry.glb'));
  const jsonLength = glb.readUInt32LE(12);
  const gltf = JSON.parse(glb.subarray(20, 20 + jsonLength));
  const binary = glb.subarray(28 + jsonLength);
  for (const [meshIndex, name] of [[1, 'berry'], [2, 'styles']]) {
    const primitive = gltf.meshes[meshIndex].primitives[0];
    const extension = primitive.extensions.KHR_draco_mesh_compression;
    const view = gltf.bufferViews[extension.bufferView];
    const bytes = binary.subarray(view.byteOffset, view.byteOffset + view.byteLength);
    const decoder = new draco.Decoder();
    const buffer = new draco.DecoderBuffer();
    buffer.Init(bytes, bytes.length);
    const mesh = new draco.Mesh();
    const status = decoder.DecodeBufferToMesh(buffer, mesh);
    if (!status.ok()) throw Error(status.error_msg());
    const count = mesh.num_points();
    const attributes = {};
    for (const key of ['POSITION', 'NORMAL', 'TEXCOORD_0', 'COLOR_0', '_CENTER']) {
      if (extension.attributes[key] === undefined) continue;
      const attribute = decoder.GetAttributeByUniqueId(mesh, extension.attributes[key]);
      const values = new draco.DracoFloat32Array();
      if (!decoder.GetAttributeFloatForAllPoints(mesh, attribute, values)) throw Error(key);
      attributes[key] = Float32Array.from({ length: values.size() }, (_, i) => values.GetValue(i));
      // Draco returns the underlying integer values for normalized COLOR_0.
      if (key === 'COLOR_0' && gltf.accessors[primitive.attributes[key]].normalized) {
        const max = gltf.accessors[primitive.attributes[key]].componentType === 5123 ? 65535 : 255;
        for (let i = 0; i < attributes[key].length; i++) attributes[key][i] /= max;
      }
      draco.destroy(values);
    }
    const vertices = new Float32Array(count * 15);
    for (let i = 0; i < count; i++) {
      let offset = i * 15;
      for (const [key, components] of [['POSITION', 3], ['NORMAL', 3], ['TEXCOORD_0', 2], ['COLOR_0', 4], ['_CENTER', 3]]) {
        const values = attributes[key];
        vertices.set(values ? values.subarray(i * components, (i + 1) * components) : [0, 1.12, 0], offset);
        offset += components;
      }
    }
    const indices = new Uint32Array(mesh.num_faces() * 3);
    const face = new draco.DracoInt32Array();
    for (let i = 0; i < mesh.num_faces(); i++) {
      decoder.GetFaceFromMesh(mesh, i, face);
      for (let j = 0; j < 3; j++) indices[i * 3 + j] = face.GetValue(j);
    }
    fs.writeFileSync(path.join(output, name + '.mesh'), Buffer.concat([
      Buffer.from('RBRY'), word(1), word(count), word(indices.length),
      Buffer.from(vertices.buffer), Buffer.from(indices.buffer)
    ]));
    console.log(name, count, 'vertices', indices.length / 3, 'triangles');
    for (const item of [face, mesh, buffer, decoder]) draco.destroy(item);
  }
  const basis = await require(path.join(source, 'basis_transcoder-o4Hde_L7.js'))({
    wasmBinary: fs.readFileSync(path.join(source, 'basis_transcoder-VXdx5NbI.wasm'))
  });
  basis.initializeBasis();
  for (const name of ['albedo', 'normal_os', 'ao_rough_thick', 'detail_normal', ...Array.from({ length: 9 }, (_, i) => 'transfer_sh' + i)]) {
    const file = new basis.KTX2File(new Uint8Array(fs.readFileSync(path.join(source, name + '.ktx2'))));
    if (!file.isValid() || !file.startTranscoding()) throw Error('Invalid texture: ' + name);
    const limit = name.startsWith('transfer') ? 1024 : 2048;
    let first = 0;
    while (Math.max(file.getWidth(), file.getHeight()) / 2 ** first > limit) first++;
    const width = Math.max(1, file.getWidth() >> first), height = Math.max(1, file.getHeight() >> first);
    const parts = [Buffer.from('RBAT'), word(width), word(height), word(file.getLevels() - first)];
    for (let level = first; level < file.getLevels(); level++) {
      // Basis format 10 = ASTC 4x4 RGBA, directly sampled by Apple GPUs.
      const bytes = new Uint8Array(file.getImageTranscodedSizeInBytes(level, 0, 0, 10));
      if (!file.transcodeImage(bytes, level, 0, 0, 10, 0, -1, -1)) throw Error('Transcode failed: ' + name);
      parts.push(word(bytes.length), Buffer.from(bytes));
    }
    fs.writeFileSync(path.join(output, name + '.texture'), Buffer.concat(parts));
    console.log(name, width, height);
    file.close(); file.delete();
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(source, 'manifest.json')));
  const fuzz = fs.readFileSync(path.join(source, manifest.fuzz.file));
  const config = manifest.fuzz;
  const strands = new Float32Array(config.count * 18);
  for (let i = 0; i < config.count; i++) {
    const base = i * 18;
    for (let j = 0; j < 12; j++) {
      const axis = j % 3;
      strands[base + j] = config.bbox_min[axis] + fuzz.readUInt16LE(i * 24 + j * 2) / 65535 * (config.bbox_max[axis] - config.bbox_min[axis]);
    }
    for (let j = 0; j < 3; j++) strands[base + 12 + j] = Math.max(-1, fuzz.readInt8(config.buffers.normal_i8.offset + i * 3 + j) / 127);
    for (let j = 0; j < 2; j++) strands[base + 15 + j] = fuzz.readUInt16LE(config.buffers.uv_u16.offset + i * 4 + j * 2) / 65535;
    strands[base + 17] = fuzz[config.buffers.meta_u8.offset + i * 4] / 255 * config.radius_unit;
  }
  fs.writeFileSync(path.join(output, 'fuzz.strands'), Buffer.concat([Buffer.from('RBFZ'), word(config.count), Buffer.from(strands.buffer)]));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
