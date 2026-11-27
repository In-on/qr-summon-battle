/* iOSアプリ版だけで読み込まれる橋渡し（WKUserScript としてページより先に実行）。
   Web版（GitHub Pages）には入らないので、Web版の動きは変わらない。index.html は変更しない。

   ゲームが使うもの:
     QRIAP.buy(商品ID) → Promise<boolean>（Apple の購入記録を確認できたら true）
     QRIAP.restore()   → Promise<number[]>（premium30d の有効な取引の購入日時ms。App Store と同期してから調べる）
     QRAd.show()       → Promise<boolean>（最後まで見たら true）
   起動時：Apple の購入記録から premium30d の購入日時を調べて window.QRPremRestore(一覧) を自動で呼ぶ。

   二重付与の防止:
     付与し終えた取引IDを localStorage（qrIapDone）に記録してから、Apple に「取引の完了」を伝える。
     同じ取引がもう一度届いても、記録にあれば付与せず完了だけ伝える。

   付与もれの防止:
     購入後、ゲームが付与する前にアプリが落ちた場合は、次回起動時にゲームの関数で付与する。
       ダイヤ        … chgAdd / addDia（ゲームの購入成功時と同じ）
       プレミアムパス … chgAdd と QRPremRestore(購入日時の一覧)（期限は購入日から計算するので二重に延びない） */
(function () {
  var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.qr;
  if (!h) return;
  var DONE_KEY = 'qrIapDone';
  var seq = 0, wait = {}, queue = [], pumping = false, bootDates = null;

  function call(cmd, args) {
    return new Promise(function (res, rej) {
      var id = ++seq;
      wait[id] = { res: res, rej: rej };
      h.postMessage({ id: id, cmd: cmd, args: args || {} });
    });
  }

  function doneList() {
    try { return JSON.parse(localStorage.getItem(DONE_KEY) || '[]'); } catch (e) { return []; }
  }
  function isDone(tx) { return doneList().indexOf(String(tx)) >= 0; }
  function markDone(tx) {
    var l = doneList(); tx = String(tx);
    if (l.indexOf(tx) < 0) l.push(tx);
    if (l.length > 300) l = l.slice(-300);
    try { localStorage.setItem(DONE_KEY, JSON.stringify(l)); } catch (e) {}
  }
  function finish(tx) {
    if (!tx) return;
    markDone(tx);
    call('iap.finish', { tx: String(tx) }).catch(function () {});
  }

  function gameReady() {
    try {
      return typeof save !== 'undefined' && save &&
        typeof window.QRPremRestore === 'function' &&
        typeof addDia === 'function' && typeof chgAdd === 'function' &&
        typeof DIA_PACK !== 'undefined' && typeof PREM !== 'undefined';
    } catch (e) { return false; }
  }
  function whenReady(fn) {
    (function step() { if (gameReady()) fn(); else setTimeout(step, 1000); })();
  }
  function premDates() { return call('iap.restore', { sync: false }).catch(function () { return []; }); }
  function applyPrem(dates) {
    try { var ok = window.QRPremRestore(dates || []); try { hudAvatar(); } catch (e) {} return ok; }
    catch (e) { console.warn(e); return false; }
  }

  /* 未付与の購入を1件ずつ付与（Promise を返す） */
  function grant(it) {
    if (it.pid === PREM.id) {
      return premDates().then(function (dates) {
        chgAdd(PREM.yen);
        applyPrem(dates);
        try { sfx('buff'); toast('前回の購入：プレミアムパスが有効になりました'); } catch (e) {}
        return true;
      });
    }
    var p = null;
    for (var i = 0; i < DIA_PACK.length; i++) if (DIA_PACK[i].id === it.pid) p = DIA_PACK[i];
    if (!p) return Promise.resolve(false);
    chgAdd(p.yen); addDia(p.n);
    try { xfNow(); } catch (e) {}
    try { sfx('buff'); toast('前回の購入：ダイヤを' + p.n + '個受け取りました'); } catch (e) {}
    return Promise.resolve(true);
  }
  function pump() {
    if (pumping) return;
    pumping = true;
    whenReady(function next() {
      var it = queue.shift();
      if (!it) { pumping = false; return; }
      if (isDone(it.tx)) { finish(it.tx); next(); return; }   // 付与済み → 完了だけ伝える
      grant(it).then(function (ok) { if (ok) finish(it.tx); }, function (e) { console.warn(e); }).then(next);
    });
  }

  window.__qrNative = {
    reply: function (id, ok, v) {
      var w = wait[id]; if (!w) return; delete wait[id];
      if (ok) w.res(v); else w.rej(new Error(String(v)));
    },
    deliver: function (list) {
      (list || []).forEach(function (it) {
        if (!queue.some(function (q) { return q.tx === it.tx; })) queue.push(it);
      });
      if (queue.length) pump();
    }
  };

  window.QRIAP = {
    native: true,
    buy: function (pid) {
      return call('iap.buy', { pid: pid }).then(function (r) {
        if (r && r.ok) {
          if (isDone(r.tx)) { finish(r.tx); return false; }   // 念のため：付与済みの取引
          // ゲームの .then（付与と保存）が先に実行されてから、記録して完了を伝える
          setTimeout(function () { finish(r.tx); }, 0);
          return true;
        }
        if (r && r.reason === 'pending') {
          try { toast('購入の承認待ちです。承認されると自動で受け取れます'); } catch (e) {}
        }
        return false;
      });
    },
    restore: function () {
      return call('iap.restore', { sync: true }).then(function (d) { return Array.isArray(d) ? d : []; });
    }
  };

  window.QRAd = {
    native: true,
    show: function () { return call('ad.show').then(function (r) { return !!r; }); }
  };

  // 起動時①：プレミアムパスを自動で復元（機種変更・再インストール対策。ダイアログは出さない）
  premDates().then(function (dates) {
    bootDates = dates;
    if (dates && dates.length) whenReady(function () { applyPrem(bootDates); });
  });
  // 起動時②：前回付与できなかった購入を確認
  call('iap.pending').then(function (list) { window.__qrNative.deliver(list); }).catch(function () {});
})();
