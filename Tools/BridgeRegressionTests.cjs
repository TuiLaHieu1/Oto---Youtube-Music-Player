// Chạy JavaScript bridge thật với DOM/timer giả; không gọi mạng hoặc tài khoản.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const swift = fs.readFileSync(path.join(__dirname, '../Oto/Services/WebKit/PlayerBridgeScript.swift'), 'utf8');
const source = swift.split('"""')[1];

function fixture() {
  const timers = [], messages = [], navigations = [];
  let video = null, moviePlayer = null, observerCallback = null;
  const app = { resolveCommand() {} };
  const document = {
    head: { appendChild() {} }, documentElement: {},
    createElement: () => ({}),
    getElementById: id => id === 'movie_player' ? moviePlayer : null,
    querySelector: selector => selector === 'video' ? video : selector === 'ytmusic-app' ? app : null,
  };
  const window = {
    location: { href: 'https://music.youtube.com/watch?v=A', assign: url => navigations.push(url) },
    addEventListener() {},
    webkit: { messageHandlers: { otoPlayback: { postMessage: value => messages.push(value) } } },
  };
  const sandbox = {
    window, document, navigator: {}, URL,
    localStorage: { getItem() {}, setItem() {}, removeItem() {} },
    MutationObserver: class {
      constructor(callback) { observerCallback = callback; }
      observe() {}
    },
    setInterval() {},
    setTimeout: (callback, delay) => { timers.push({ callback, delay }); },
  };
  const diagnostics = fs.readFileSync(
    path.join(__dirname, '../Oto/Services/WebKit/PlayerDiagnosticScript.swift'), 'utf8'
  ).split('"""')[1];
  vm.runInNewContext(diagnostics, sandbox);
  vm.runInNewContext(source, sandbox);
  return {
    window, timers, messages, navigations,
    setVideo: value => { video = value; },
    setMoviePlayer: value => { moviePlayer = value; },
    triggerObserver: () => { if (observerCallback) observerCallback(); },
  };
}

{
  const f = fixture();
  let plays = 0;
  f.window.otoPlayer.adoptLoadedVideo('A', 35, 1, true);
  const staleTimer = f.timers.find(timer => timer.delay === 150);
  assert.ok(staleTimer, 'A phải đang đợi media element');
  const video = { currentTime: 0, paused: true, readyState: 4, play() { plays++; }, pause() {} };
  f.setVideo(video);
  f.window.location.href = 'https://music.youtube.com/watch?v=B';
  f.window.otoPlayer.adoptCurrentVideo('B', 0, 2, false);
  staleTimer.callback();
  assert.equal(video.currentTime, 0, 'Timer A không được seek B');
  assert.equal(plays, 0, 'Timer A không được play B');
}

{
  const f = fixture();
  f.window.otoPlayer.loadVideo('A', 0, 1, true);
  const staleFallback = f.timers.find(timer => timer.delay === 750);
  assert.ok(staleFallback);
  f.window.otoPlayer.loadVideo('B', 0, 2, false);
  staleFallback.callback();
  assert.equal(f.navigations.length, 0, 'SPA fallback A không được quay lại bài cũ');
}

{
  const f = fixture();
  let oldPlays = 0;
  const oldVideo = {
    currentTime: 0, paused: true, readyState: 4,
    play() { oldPlays++; return { catch(handler) { handler(); } }; },
  };
  f.setVideo(oldVideo);
  f.window.otoPlayer.adoptCurrentVideo('A', 0, 1, true);
  const staleRetry = f.timers.find(timer => timer.delay === 250);
  assert.ok(staleRetry);
  f.setVideo({ currentTime: 0, paused: true, readyState: 4, play() {} });
  f.window.location.href = 'https://music.youtube.com/watch?v=B';
  f.window.otoPlayer.adoptCurrentVideo('B', 0, 2, true);
  staleRetry.callback();
  assert.equal(oldPlays, 1, 'Retry promise A không được phát media element cũ');
}

{
  const f = fixture();
  f.window.__otoCurrentGeneration = 10;
  for (let i = 0; i < 5; i++) f.window.otoReportPlaybackDiagnostic('playRejected', 'NotAllowedError');
  const initialTimers = f.timers.length;
  f.window.otoSchedulePlaybackDiagnostics('track', 10);
  f.window.otoSchedulePlaybackDiagnostics('track', 10);
  assert.equal(f.timers.length - initialTimers, 3, 'Một request chỉ có ba timer diagnostic');
  const rejections = f.messages.filter(message => message.type === 'playbackDiagnostic');
  assert.equal(rejections.length, 1, 'Rejection log phải được giới hạn theo generation');
  assert.equal(rejections[0].error, 'NotAllowedError');
  f.window.__otoCurrentGeneration = 11;
  f.window.otoReportPlaybackDiagnostic('playRejected', 'sensitive-error-message');
  assert.equal(f.messages.at(-1).error, 'OtherError', 'Không gửi raw exception text');
}

{
  const f = fixture();
  let apiPlays = 0, domPlays = 0;
  f.setMoviePlayer({ playVideo() { apiPlays++; }, seekTo() {} });
  f.setVideo({ currentTime: 0, paused: true, readyState: 4, play() { domPlays++; } });
  f.window.otoPlayer.adoptCurrentVideo('A', 0, 1, true);
  assert.equal(apiPlays, 1, 'Adopt chỉ phát một lần qua API được chọn');
  assert.equal(domPlays, 0, 'Không gọi DOM play song song với player API');
  f.window.otoPlayer.play();
  assert.equal(apiPlays, 2, 'Resume chỉ gửi một lệnh play');
  assert.equal(domPlays, 0);
}

{
  const f = fixture();
  let domPlays = 0;
  f.setMoviePlayer({ playVideo() { throw new Error('unavailable'); } });
  f.setVideo({ currentTime: 0, paused: true, readyState: 4, play() { domPlays++; } });
  f.window.otoPlayer.adoptLoadedVideo('A', 0, 1, true);
  assert.equal(domPlays, 1, 'API ném lỗi thì mới fallback sang DOM');
}

{
  const f = fixture();
  const handlers = {};
  const video = {
    currentTime: 0, duration: 100, paused: true, readyState: 4, muted: false,
    addEventListener(name, handler) { handlers[name] = handler; },
    play() { this.paused = false; },
    pause() { this.paused = true; },
  };
  f.window.otoPlayer.loadVideo('A', 0, 1, true);
  f.setVideo(video);
  f.triggerObserver();
  video.currentTime = 100;
  if (handlers.ended) handlers.ended();
  assert.equal(f.messages.filter(message => message.type === 'trackEnded').length, 0,
    'Ended trễ trước khi media mới phát không được chuyển bài');
  if (handlers.playing) handlers.playing();
  if (handlers.ended) handlers.ended();
  if (handlers.ended) handlers.ended();
  const firstEnds = f.messages.filter(message => message.type === 'trackEnded');
  assert.equal(firstEnds.length, 1, 'Ended trùng chỉ báo một lần');
  assert.equal(firstEnds[0].generation, 1);

  f.window.otoPlayer.loadVideo('A', 0, 2, true);
  video.currentTime = 100;
  if (handlers.ended) handlers.ended();
  assert.equal(f.messages.filter(message => message.type === 'trackEnded').length, 1,
    'Ended cũ không được gắn generation mới');
  if (handlers.playing) handlers.playing();
  if (handlers.ended) handlers.ended();
  const allEnds = f.messages.filter(message => message.type === 'trackEnded');
  assert.equal(allEnds.length, 2);
  assert.equal(allEnds[1].generation, 2);
}

{
  const f = fixture();
  const handlers = {};
  const mediaSession = { setActionHandler(action, handler) { handlers[action] = handler; } };
  const sandbox = {
    window: f.window,
    document: {
      head: { appendChild() {} }, documentElement: {}, createElement: () => ({}),
      getElementById: () => null, querySelector: () => null,
    },
    navigator: { mediaSession }, URL,
    localStorage: { getItem() {}, setItem() {}, removeItem() {} },
    MutationObserver: class { observe() {} }, setInterval() {}, setTimeout() {},
  };
  delete f.window.__otoScriptInjected;
  vm.runInNewContext(source, sandbox);
  assert.equal(handlers.seekforward, null);
  assert.equal(handlers.seekbackward, null);
  assert.equal(typeof handlers.play, 'function');
  assert.equal(typeof handlers.pause, 'function');
  assert.equal(typeof handlers.nexttrack, 'function');
  assert.equal(typeof handlers.previoustrack, 'function');
  f.window.__otoCurrentVideoId = 'A';
  f.window.__otoCurrentGeneration = 1;
  handlers.nexttrack();
  handlers.previoustrack();
  assert.equal(f.messages.at(-2).command, 'next');
  assert.equal(f.messages.at(-1).command, 'previous');
  handlers.pause();
  assert.equal(f.window.__otoUserPaused, true, 'Pause từ Lock Screen chặn auto-play ngay');
  assert.equal(f.messages.at(-1).command, 'pause');
  handlers.play();
  assert.equal(f.window.__otoUserPaused, false, 'Play từ Lock Screen cập nhật intent bridge');
  assert.equal(f.messages.at(-1).command, 'play');
}

for (const method of ['adoptLoadedVideo', 'adoptCurrentVideo']) {
  const f = fixture();
  let active = 'B';
  let loaded;
  f.setMoviePlayer({
    getVideoData: () => ({ video_id: active }),
    loadVideoById: id => { loaded = id; active = id; },
  });
  f.window.otoPlayer[method]('A', 0, 5, true);
  assert.equal(loaded, 'A', 'Metadata cũ không được dùng để nhận nhầm video B');
  assert.ok(f.messages.some(m => m.type === 'trackActivated' && m.videoId === 'A' && m.generation === 5));
}

{
  const f = fixture();
  let loads = 0;
  // Lặp cùng video đã tới cuối phải nạp lại đúng ID, tránh tranh chấp với tự chuyển bài của web.
  const ended = { ended: true };
  f.setVideo(ended);
  f.setMoviePlayer({
    getVideoData: () => ({ video_id: 'A' }),
    loadVideoById(id) { assert.equal(id, 'A'); loads++; },
  });
  for (let generation = 2; generation <= 4; generation++) {
    f.window.otoPlayer.adoptCurrentVideo('A', 0, generation, false);
  }
  assert.equal(loads, 3);
}
console.log('PASS: hồi quy bridge, gồm ba lượt Restart trên video đã kết thúc');

async function testVideoPresentation() {
  const swift = fs.readFileSync(path.join(__dirname, '../Oto/Services/WebKit/PlayerWebViewContainer.swift'), 'utf8');
  const source = swift.split('"""')[1];
  const attributes = new Map();
  let visible = false;
  let style;
  const video = {
    readyState: 2, videoWidth: 1280, videoHeight: 720,
    showPopover() { visible = true; },
    hidePopover() { visible = false; },
    matches: () => visible,
    hasAttribute: key => attributes.has(key),
    setAttribute: (key, value) => attributes.set(key, value),
    removeAttribute: key => attributes.delete(key),
    getBoundingClientRect: () => ({ width: 320, height: 180 }),
  };
  const document = {
    querySelector(selector) {
      if (selector === '#movie_player video') return video;
      if (selector === 'video[data-oto-video-presentation]' && attributes.has('data-oto-video-presentation')) {
        return video;
      }
      return null;
    },
    getElementById: id => id === 'movie_player' ? null : style,
    createElement: () => ({ remove() { style = undefined; } }),
    head: { append(element) { style = element; } },
  };
  const present = vm.runInNewContext(`(async showsVideo => {${source}})`, {
    document, window: {}, location: { origin: 'https://music.youtube.com' },
    setTimeout: resolve => resolve(),
  });
  assert.equal(await present(true), 'ready');
  assert.equal(visible, true);
  assert.equal(await present(false), 'artwork');
  assert.equal(attributes.size, 0);
  assert.equal(visible, false);
  assert.equal(style, undefined);
  video.videoWidth = 0;
  assert.equal(await present(true), 'no-video-frame');
  assert.equal(visible, false);
  console.log('PASS: lớp hiển thị video, hoàn tác ảnh bìa và dự phòng khi không có khung hình');
}

testVideoPresentation().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
