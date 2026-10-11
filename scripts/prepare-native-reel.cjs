// Extract only the original parameter/shot literals; never execute the web app.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'web/assets/index-DQDjxRl6.js'), 'utf8');
function literal(name) {
  const start = source.indexOf(`${name}=`) + name.length + 1;
  if (start < name.length + 1 || !'{['.includes(source[start])) throw Error(`Missing ${name}`);
  let depth = 0, quote = null, escaped = false;
  for (let end = start; end < source.length; end++) {
    const c = source[end];
    if (quote) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === quote) quote = null;
    } else if ('"\'`'.includes(c)) quote = c;
    else if ('{['.includes(c)) depth++;
    else if ('}]'.includes(c) && --depth === 0) return source.slice(start, end + 1);
  }
  throw Error(`Unclosed ${name}`);
}
const evaluate = text => vm.runInNewContext(`(${text})`, { sf: { intensity: 0 } }, { timeout: 1000 });
const defaults = evaluate(literal('tf'));
const overrides = evaluate(literal('cf'));
const shots = evaluate(literal('bp'));
function merge(a, b) {
  for (const [key, value] of Object.entries(b)) {
    if (value && typeof value === 'object' && !Array.isArray(value)) a[key] = merge(a[key] || {}, value);
    else a[key] = value;
  }
  return a;
}
const looks = Object.fromEntries(Object.keys(overrides).map(name => [name,
  merge(JSON.parse(JSON.stringify(defaults)), overrides[name] || {})]));
const data = { shots, looks, options: defaults.reel, fov: defaults.camera.fov };
fs.writeFileSync(path.join(root, 'NativeAssets/reel.json'), JSON.stringify(data, null, 2) + '\n');
console.log(`Extracted ${shots.length} original reel shots (${shots.reduce((sum, s) => sum + s.beats, 0) * defaults.reel.beat}s)`);

// Optional parity fixtures use the original playback function unchanged.
if (process.argv[2]) {
  const start = source.indexOf('function Tp(');
  const end = source.indexOf('function Ep(', start);
  const context = { bp: shots, xp: evaluate(literal('xp')), Sp: (v, t, fallback = 0) => v == null ? fallback : Array.isArray(v) ? v[0] + (v[1] - v[0]) * t : v,
    Cp: Math.PI / 180, wp: shots.reduce((sum, s) => sum + s.beats, 0), nf: {}, cf: overrides };
  const makeReel = vm.runInNewContext(`(${source.slice(start, end).trim()})`, context);
  const scenarios = [];
  for (const aspect of [440 / 956, 257 / 511]) {
    for (const dt of [1 / 60, 1 / 30, 0.1]) {
      let position, target, roll, preset, blur;
      const camera = { fov: data.fov, position: { set: (...v) => position = v }, lookAt: (...v) => target = v, rotateZ: v => roll = v, updateProjectionMatrix() {} };
      const reel = makeReel({ params: { reel: defaults.reel, camera: defaults.camera }, camera,
        setLook: shot => { preset = shot.preset; blur = shot.bokeh ?? looks[preset].post.bokehScale; } });
      reel.start(17);
      const frames = [];
      for (let i = 0; i < Math.ceil(reel.duration * 2.1 / dt); i++) {
        const frame = reel.update(dt, aspect);
        frames.push({ ...frame, position, target, roll, preset, blur, fov: camera.fov, time: reel.time });
      }
      scenarios.push({ aspect, dt, frames });
    }
  }
  fs.writeFileSync(process.argv[2], JSON.stringify(scenarios));
}
