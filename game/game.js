const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');

const player = { x: canvas.width / 2 - 20, y: canvas.height - 30, w: 40, h: 20, speed: 5 };
let bullets = [];
let enemies = [];
let lastShot = 0;
let lastEnemy = 0;

const keys = {};
document.addEventListener('keydown', e => keys[e.key] = true);
document.addEventListener('keyup', e => keys[e.key] = false);

function shoot() {
  bullets.push({ x: player.x + player.w / 2 - 2, y: player.y, w: 4, h: 10, speed: 7 });
}

function spawnEnemy() {
  const x = Math.random() * (canvas.width - 30);
  enemies.push({ x, y: -20, w: 30, h: 20, speed: 2 });
}

function update(time) {
  requestAnimationFrame(update);
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  if (keys['ArrowLeft']) player.x -= player.speed;
  if (keys['ArrowRight']) player.x += player.speed;
  player.x = Math.max(0, Math.min(canvas.width - player.w, player.x));

  if (keys[' '] && time - lastShot > 300) {
    shoot();
    lastShot = time;
  }

  if (time - lastEnemy > 1000) {
    spawnEnemy();
    lastEnemy = time;
  }

  bullets.forEach(b => b.y -= b.speed);
  enemies.forEach(e => e.y += e.speed);

  bullets.forEach((b, bi) => {
    enemies.forEach((e, ei) => {
      if (b.x < e.x + e.w && b.x + b.w > e.x && b.y < e.y + e.h && b.y + b.h > e.y) {
        bullets.splice(bi, 1);
        enemies.splice(ei, 1);
      }
    });
  });

  bullets = bullets.filter(b => b.y + b.h > 0);
  enemies = enemies.filter(e => e.y < canvas.height);

  ctx.fillStyle = 'white';
  ctx.fillRect(player.x, player.y, player.w, player.h);

  ctx.fillStyle = 'yellow';
  bullets.forEach(b => ctx.fillRect(b.x, b.y, b.w, b.h));

  ctx.fillStyle = 'red';
  enemies.forEach(e => ctx.fillRect(e.x, e.y, e.w, e.h));
}

requestAnimationFrame(update);
