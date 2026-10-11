// Reference fixtures execute only the original orbit-control class.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../web/assets/index-DQDjxRl6.js'), 'utf8');
const start = source.indexOf('Np=Math.PI/180');
const end = source.indexOf('Rp=`/assets/`', start);
const controls = source.slice(start, end).replace(/,$/, '');
class Vector {
  constructor(x = 0, y = 0, z = 0) { Object.assign(this, { x, y, z }); }
  clone() { return new Vector(this.x, this.y, this.z); }
  sub(v) { this.x -= v.x; this.y -= v.y; this.z -= v.z; return this; }
  length() { return Math.hypot(this.x, this.y, this.z); }
  copy(v) { return this.set(v.x, v.y, v.z); }
  set(x, y, z) { Object.assign(this, { x, y, z }); return this; }
  distanceToSquared(v) { return (this.x - v.x) ** 2 + (this.y - v.y) ** 2 + (this.z - v.z) ** 2; }
}
const Orbit = vm.runInNewContext(`(() => { let Np,Pp,Fp,Ip,Lp; ${controls}; return Lp; })()`,
  { W: Vector, window: { matchMedia: () => ({ matches: false }) } });
const scenarios = [];
for (const aspect of [440 / 956, 257 / 511]) {
  const camera = { position: new Vector(1.57, 3.4, 8.98), lookAt() {} };
  const dom = { style: {}, addEventListener() {}, setPointerCapture() {}, releasePointerCapture() {} };
  const orbit = new Orbit(camera, dom);
  orbit.setFit(Math.max(1, 0.86 / aspect));
  orbit.autoRotate = true;
  orbit.playIntro();
  const frames = [];
  const capture = () => { frames.push({ position: [camera.position.x, camera.position.y, camera.position.z], radius: orbit.cur.radius, lightTurn: orbit.lightTurn }); };
  for (let i = 0; i < 240; i++) { orbit.update(1 / 60); capture(); }
  orbit.autoRotate = false;
  const event = (id, x) => ({ pointerId: id, clientX: x, clientY: 0, timeStamp: 5000, pointerType: 'touch' });
  orbit.onDown(event(1, -60)); orbit.onDown(event(2, 60));
  for (const scale of [1.25, 2, 4]) {
    orbit.onMove(event(1, -60 * scale)); orbit.onMove(event(2, 60 * scale));
    for (let i = 0; i < 60; i++) { orbit.update(1 / 60); capture(); }
  }
  orbit.onUp(event(1, -240)); orbit.onUp(event(2, 240));
  orbit.goHome();
  for (let i = 0; i < 120; i++) { orbit.update(1 / 60); capture(); }
  scenarios.push({ aspect, frames });
}
fs.writeFileSync(process.argv[2], JSON.stringify(scenarios));
console.log('Extracted original intro, pinch zoom, and reset camera trajectories');
