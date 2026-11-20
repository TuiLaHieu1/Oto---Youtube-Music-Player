// Chạy JavaScript bridge thật với DOM/timer giả; không gọi mạng hoặc tài khoản.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const swift = fs.readFileSync(path.join(__dirname, '../Oto/Services/WebKit/PlayerBridgeScript.swift'), 'utf8');
const source = swift.split('"""')[1];

function fixture() {
  const timers = [], messages = [], navigations = [];
  const mediaActions = {};
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
    window, document, navigator: { mediaSession: {
      setActionHandler(action, handler) { mediaActions[action] = handler; },
    } }, URL,
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
    window, document, mediaActions, timers, messages, navigations,
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
  const handlers = f.mediaActions;
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
  f.mediaActions.pause();
  f.document.visibilityState = 'visible';
  f.document.hasFocus = () => true;
  f.mediaActions.play();
  const commands = () => f.messages.filter(message => message.type === 'remoteCommand')
    .map(message => message.command).slice(2);
  assert.deepEqual(commands(), ['pause'], 'Play giao lúc mở lại trang không được đổi ý định pause');
  f.document.hasFocus = () => false;
  f.mediaActions.play();
  f.document.visibilityState = 'hidden';
  f.mediaActions.play();
  assert.deepEqual(commands(), ['pause', 'play', 'play']);
  assert.equal(f.window.__otoUserPaused, true, 'Chờ native xác nhận Play trước khi mở khóa pause');
  f.window.otoPlayer.play();
  assert.equal(f.window.__otoUserPaused, false);
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

{
  // PlayerIntentScript: đã dừng thì thẻ media không được tự chạy, đang phát thì không bị chặn.
  const intent = fs.readFileSync(
    path.join(__dirname, '../Oto/Services/WebKit/PlayerIntentScript.swift'), 'utf8'
  ).split('"""')[1];
  const ticks = [];
  const video = { paused: false, ended: false, pause() { this.paused = true; } };
  const calls = [];
  const otoPlayer = {};
  for (const name of ['play', 'pause', 'loadVideo', 'adoptLoadedVideo', 'adoptCurrentVideo']) {
    otoPlayer[name] = () => { calls.push(name); };
  }
  const window = { otoPlayer, __otoUserPaused: true };
  vm.runInNewContext(intent, {
    window, document: { querySelector: selector => selector === 'video' ? video : null },
    setInterval: callback => { ticks.push(callback); }, setTimeout() {},
  });
  assert.equal(window.__otoPauseGuard, false, 'Mặc định chưa chặn để lần nạp đầu không bị dừng');
  ticks[0]();
  assert.equal(video.paused, false, 'Chưa có lệnh dừng thì không đụng media');
  window.otoPlayer.pause();
  assert.equal(window.__otoPauseGuard, true);
  assert.deepEqual(calls, ['pause'], 'Hàm gốc vẫn được gọi');
  ticks[0]();
  assert.equal(video.paused, true, 'Đã dừng thì media tự chạy lại phải bị dừng');
  video.paused = false;
  window.__otoUserPaused = false;
  ticks[0]();
  assert.equal(video.paused, false, 'Cờ dừng của bridge đã tắt thì không chặn');
  window.__otoUserPaused = true;
  window.otoPlayer.play();
  ticks[0]();
  assert.equal(video.paused, false, 'play() tắt chế độ chặn');
  window.otoPlayer.loadVideo('A', 0, 1, false);
  assert.equal(window.__otoPauseGuard, true, 'Nạp không phát thì bật chặn');
  window.otoPlayer.adoptCurrentVideo('A', 0, 2, true);
  assert.equal(window.__otoPauseGuard, false, 'Nạp có phát thì tắt chặn');
  console.log('PASS: PlayerIntentScript giữ ý định dừng và không chặn lệnh phát');
}
{
  // PlayerPlayabilityScript: báo mã lỗi của player và màn hình lỗi, mỗi lỗi một lần cho mỗi bài.
  const script = fs.readFileSync(
    path.join(__dirname, '../Oto/Services/WebKit/PlayerPlayabilityScript.swift'), 'utf8'
  ).split('"""')[1];
  const posted = [], ticks = [];
  let errorHandler = null, errorText = '';
  const player = {
    addEventListener(name, handler) { if (name === 'onError') errorHandler = handler; },
    querySelector: () => errorText ? { textContent: errorText } : null,
  };
  const window = {
    __otoCurrentGeneration: 3, __otoCurrentVideoId: 'VEVO1',
    webkit: { messageHandlers: { otoPlayback: { postMessage: value => posted.push(value) } } },
  };
  vm.runInNewContext(script, {
    window, document: { getElementById: id => id === 'movie_player' ? player : null },
    setInterval: callback => { ticks.push(callback); }, WeakSet, Number, Math, String,
  });
  ticks[0]();
  assert.equal(posted.length, 0, 'Không lỗi thì không báo');
  errorHandler({ data: 150 });
  errorHandler({ data: 150 });
  assert.deepEqual(JSON.parse(JSON.stringify(posted)),
    [{ type: 'error', code: 150, generation: 3, videoId: 'VEVO1' }], 'Cùng lỗi chỉ báo một lần');
  errorText = 'Video unavailable';
  ticks[0]();
  assert.equal(posted.at(-1).code, 150);
  window.__otoCurrentVideoId = 'NEXT';
  errorText = '';
  errorHandler({ data: 101 });
  assert.equal(posted.at(-1).code, 101);
  assert.equal(posted.at(-1).videoId, 'NEXT', 'Lỗi gắn đúng bài hiện tại');
  console.log('PASS: PlayerPlayabilityScript báo lỗi player một lần cho mỗi bài');
}
async function testVideoPresentation() {
  const swift = fs.readFileSync(path.join(__dirname, '../Oto/Services/WebKit/PlayerWebViewContainer.swift'), 'utf8');
  const source = swift.split('"""')[1];
  const attributes = new Map();
  let visible = false;
  let style;
  let layoutReads = 0;
  let alwaysZeroBounds = false;
  const video = {
    readyState: 2, videoWidth: 1280, videoHeight: 720,
    showPopover() { visible = true; },
    hidePopover() { visible = false; },
    matches: () => visible,
    hasAttribute: key => attributes.has(key),
    setAttribute: (key, value) => attributes.set(key, value),
    removeAttribute: key => attributes.delete(key),
    getBoundingClientRect: () => (++layoutReads === 1 || alwaysZeroBounds
      ? { width: 0, height: 0 } : { width: 320, height: 180 }),
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
  assert.equal(layoutReads, 2, 'Đợi layout WebKit sau khi mở video');
  assert.equal(await present(false), 'artwork');
  assert.equal(attributes.size, 0);
  assert.equal(visible, false);
  assert.equal(style, undefined);
  alwaysZeroBounds = true;
  assert.equal(await present(true), 'no-visible-bounds');
  assert.equal(await present(false), 'artwork');
  video.videoWidth = 0;
  assert.equal(await present(true), 'no-video-frame');
  assert.equal(visible, false);
  console.log('PASS: lớp hiển thị video, hoàn tác ảnh bìa và dự phòng khi không có khung hình');
}

testVideoPresentation().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
