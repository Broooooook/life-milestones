/**
 * 生涯里程 — 匯出到 Google 文件與 Google 試算表
 *
 * 使用方式（只要做一次）：
 * 1. 到 https://script.google.com 按「新專案」，把這整份程式碼貼上，取代原本的內容，按儲存。
 * 2. 右上角「部署」→「新增部署作業」→ 齒輪選「網頁應用程式」
 *    執行身分：我　／　誰可以存取：所有人
 * 3. 按「部署」，依畫面授權（會看到「Google 尚未驗證這個應用程式」→ 進階 → 前往（不安全）→ 允許，
 *    這是你自己寫給自己用的程式，所以會有這個提示）。
 * 4. 複製「網頁應用程式網址」，貼到 APP 的「設定 → 匯出到 Google」。
 *
 * 安全：APP 第一次匯出時會把它的配對金鑰存在這裡，之後只接受同一把金鑰。
 * 想換手機重新配對：用 APP 裡的「配對碼」，或在編輯器執行 resetPairing。
 *
 * 照片會上傳到「生涯里程/照片」資料夾，每張只傳一次，並以縮圖放進文件。
 *
 * 每次匯出都是「整份重寫」（單向：APP → Google），請不要直接在匯出的文件裡修改，
 * 下次匯出會被覆蓋。文件和試算表會放在雲端硬碟的「生涯里程」資料夾。
 */

var FOLDER_NAME = '生涯里程';
var FILE_NAME = '生涯里程記事（APP 備份）';

function doGet() {
  var paired = !!PropertiesService.getScriptProperties().getProperty('pairKey');
  return json_({ ok: true, service: 'life-milestones', paired: paired });
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    var data = JSON.parse(e.postData.contents);
    var props = PropertiesService.getScriptProperties();
    var pairKey = props.getProperty('pairKey');
    if (!data.key || String(data.key).length < 16) return json_({ ok: false, error: '缺少配對金鑰' });
    if (!pairKey) {
      props.setProperty('pairKey', data.key);
    } else if (pairKey !== data.key) {
      return json_({ ok: false, error: '配對金鑰不符：這個網址已經和另一支手機配對' });
    }
    if (data.ping) return json_({ ok: true, ping: true });

    // 照片：先問缺哪些，再一張一張上傳
    if (data.action === 'missingPhotos') {
      var all = props.getProperties();
      var missing = (data.names || []).filter(function (n) { return !all['ph:' + n]; });
      return json_({ ok: true, missing: missing });
    }
    if (data.action === 'uploadPhoto') {
      if (!/^[A-Za-z0-9_.-]+$/.test(String(data.name))) return json_({ ok: false, error: '照片檔名不正確' });
      var blob = Utilities.newBlob(Utilities.base64Decode(data.data), 'image/jpeg', data.name);
      var pf = photoFolder_(folder_());
      var file = pf.createFile(blob);
      props.setProperty('ph:' + data.name, file.getId());
      return json_({ ok: true });
    }

    // 還原：回傳最近一次匯出的完整備份
    if (data.action === 'restore') {
      var bid = props.getProperty('backupId');
      if (!bid) return json_({ ok: true, backup: null });
      var text = DriveApp.getFileById(bid).getBlob().getDataAsString('UTF-8');
      return json_({ ok: true, backup: JSON.parse(text) });
    }
    if (data.action === 'getPhoto') {
      var pid = props.getProperty('ph:' + data.name);
      if (!pid) return json_({ ok: false, error: '找不到照片' });
      return json_({ ok: true, data: Utilities.base64Encode(DriveApp.getFileById(pid).getBlob().getBytes()) });
    }

    var events = (data.events || []).slice().sort(function (a, b) {
      return sortKey_(a.start) - sortKey_(b.start);
    });
    var folder = folder_();
    writeBackup_(events, props, folder, data.exportedAt);
    var doc = writeDoc_(events, props, folder);
    var sheet = writeSheet_(events, props, folder);
    return json_({ ok: true, docUrl: doc.getUrl(), sheetUrl: sheet.getUrl(), count: events.length });
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}

function folder_() {
  var it = DriveApp.getFoldersByName(FOLDER_NAME);
  return it.hasNext() ? it.next() : DriveApp.createFolder(FOLDER_NAME);
}

// 完整備份（給 APP 還原用）
function writeBackup_(events, props, folder, exportedAt) {
  var text = JSON.stringify({ version: 2, exportedAt: exportedAt || new Date().toISOString(), events: events });
  var id = props.getProperty('backupId');
  if (id) {
    try {
      var f = DriveApp.getFileById(id);
      if (!f.isTrashed()) { f.setContent(text); return; }
    } catch (err) {}
  }
  var made = folder.createFile('生涯里程備份（APP 還原用，請勿修改）.json', text, 'application/json');
  props.setProperty('backupId', made.getId());
}

// 換手機又沒有配對碼時：在編輯器選這個函式按「執行」，就能讓新手機重新配對
function resetPairing() {
  PropertiesService.getScriptProperties().deleteProperty('pairKey');
}

function photoFolder_(parent) {
  var it = parent.getFoldersByName('照片');
  return it.hasNext() ? it.next() : parent.createFolder('照片');
}

function openOrCreate_(props, key, create, open) {
  var id = props.getProperty(key);
  if (id) {
    try {
      var f = DriveApp.getFileById(id);
      if (!f.isTrashed()) return open(id);
    } catch (err) {}
  }
  var made = create();
  props.setProperty(key, made.getId());
  return made;
}

function pad_(n) { return (n < 10 ? '0' : '') + n; }
function fmt_(d) {
  if (!d) return '';
  var s = '' + d.y;
  if (d.m) s += '/' + pad_(d.m);
  if (d.d) s += '/' + pad_(d.d);
  return s;
}
function sortKey_(d) { return d.y * 10000 + (d.m || 0) * 100 + (d.d || 0); }
function money_(v) { return String(v).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
function wan_(v) { return (Math.round(v / 1000) / 10) + ' 萬'; }

function writeDoc_(events, props, folder) {
  var doc = openOrCreate_(props, 'docId', function () {
    var d = DocumentApp.create(FILE_NAME);
    DriveApp.getFileById(d.getId()).moveTo(folder);
    return d;
  }, function (id) { return DocumentApp.openById(id); });

  var H = DocumentApp.ParagraphHeading;
  var body = doc.getBody();
  body.clear();
  var titleP = body.getParagraphs()[0];
  titleP.setText('生涯里程記事');
  titleP.setHeading(H.TITLE);

  var first = events.length ? events[0].start.y : '';
  var last = events.length ? events[events.length - 1].start.y : '';
  var tz = Session.getScriptTimeZone();
  var info = body.appendParagraph(first + ' – ' + last + '・共 ' + events.length + ' 筆・' +
    Utilities.formatDate(new Date(), tz, 'yyyy/MM/dd HH:mm') + ' 由 APP 匯出');
  info.setHeading(H.NORMAL);
  info.editAsText().setFontSize(10).setForegroundColor('#6b655b').setItalic(true);

  var byYear = {};
  var years = [];
  events.forEach(function (e) {
    if (!byYear[e.start.y]) { byYear[e.start.y] = []; years.push(e.start.y); }
    byYear[e.start.y].push(e);
  });

  years.forEach(function (y) {
    var list = byYear[y];
    var hp = body.appendParagraph(y + ' 年').setHeading(H.HEADING1);
    hp.setIndentStart(0).setIndentFirstLine(0);
    hp.editAsText().setFontSize(18).setBold(true).setItalic(false).setForegroundColor('#0f5e5c');

    // 年度摘要：所得、紅利、調薪
    var income = null, bonus = 0, raise = 0, hasRaise = false;
    list.forEach(function (e) {
      if (e.amount == null) return;
      if (!e.start.m && /^年(度)?(所得|收入)/.test(e.title)) income = e.amount;
      if (e.title.indexOf('紅利') >= 0) bonus += e.amount;
      if (e.title.indexOf('調薪') >= 0) { raise += e.amount; hasRaise = true; }
    });
    var parts = [];
    if (income != null) parts.push('所得 ' + wan_(income));
    if (bonus) parts.push('紅利 ' + wan_(bonus));
    if (hasRaise) parts.push('調薪 ' + money_(raise) + ' 元');
    parts.push(list.length + ' 筆');
    var sum = body.appendParagraph(parts.join('｜'));
    sum.setHeading(H.NORMAL);
    sum.setIndentStart(0).setIndentFirstLine(0);
    sum.editAsText().setFontSize(10).setForegroundColor('#6b655b').setBold(false).setItalic(false);

    list.forEach(function (e) {
      var label = e.start.d ? pad_(e.start.m) + '/' + pad_(e.start.d) : (e.start.m ? e.start.m + ' 月' : '全年');
      var text = (e.starred ? '★ ' : '') + e.title;
      if (e.amount != null) text += '（' + money_(e.amount) + ' 元）';
      if (e.end) text += '　～' + fmt_(e.end);
      if (e.people && e.people.length) text += '　— ' + e.people.join('、');
      text += '　〔' + e.category + '〕';

      var full = label + '　' + text;
      var p = body.appendParagraph(full);
      p.setHeading(H.NORMAL);
      p.setSpacingBefore(4);
      p.setIndentStart(0).setIndentFirstLine(0);
      var pt = p.editAsText();
      pt.setBold(false).setItalic(false).setFontSize(11).setForegroundColor('#1d1b18');
      pt.setBold(0, label.length - 1, true);
      var catStart = full.lastIndexOf('〔');
      pt.setForegroundColor(catStart, full.length - 1, '#8a8376');
      pt.setFontSize(catStart, full.length - 1, 9);

      if (e.note) {
        String(e.note).split('\n').forEach(function (line) {
          var np = body.appendParagraph(line);
          np.setHeading(H.NORMAL);
          np.setIndentStart(42).setIndentFirstLine(42);
          np.setSpacingBefore(0);
          np.editAsText().setFontSize(10).setBold(false).setItalic(false).setForegroundColor('#5f5a52');
        });
      }

      if (e.photos && e.photos.length) {
        var pp = body.appendParagraph('');
        pp.setHeading(H.NORMAL);
        pp.setIndentStart(42).setIndentFirstLine(42);
        pp.setSpacingBefore(4);
        e.photos.forEach(function (n) {
          var id = props.getProperty('ph:' + n);
          if (!id) return;
          try {
            var img = pp.appendInlineImage(DriveApp.getFileById(id).getBlob());
            var w = img.getWidth(), h = img.getHeight(), tw = 150;
            if (w > 0) img.setWidth(tw).setHeight(Math.round(h * tw / w));
            pp.appendText(' ');
          } catch (err) {}
        });
      }
    });
  });

  doc.saveAndClose();
  return DocumentApp.openById(doc.getId());
}

function writeSheet_(events, props, folder) {
  var ss = openOrCreate_(props, 'sheetId', function () {
    var s = SpreadsheetApp.create(FILE_NAME);
    DriveApp.getFileById(s.getId()).moveTo(folder);
    return s;
  }, function (id) { return SpreadsheetApp.openById(id); });

  var sh = ss.getSheets()[0];
  sh.setName('事件');
  sh.clear();
  var rows = [['日期', '結束日期', '年', '分類', '標題', '金額', '備註', '照片', '標記', '人物', 'ID']];
  events.forEach(function (e) {
    var n = (e.photos || []).length;
    rows.push([fmt_(e.start), fmt_(e.end), e.start.y, e.category, e.title,
      e.amount == null ? '' : e.amount, e.note || '', n ? n + ' 張' : '', e.starred ? '★' : '',
      (e.people || []).join('、'), e.id]);
  });
  sh.getRange(1, 1, rows.length, 2).setNumberFormat('@');
  sh.getRange(1, 1, rows.length, rows[0].length).setValues(rows);
  if (rows.length > 1) sh.getRange(2, 6, rows.length - 1, 1).setNumberFormat('#,##0');
  sh.getRange(1, 1, 1, rows[0].length).setFontWeight('bold').setBackground('#efeadf');
  sh.setFrozenRows(1);
  sh.setColumnWidth(1, 95); sh.setColumnWidth(2, 95); sh.setColumnWidth(3, 50);
  sh.setColumnWidth(4, 70); sh.setColumnWidth(5, 280); sh.setColumnWidth(6, 90);
  sh.setColumnWidth(7, 380); sh.setColumnWidth(8, 55); sh.setColumnWidth(9, 45); sh.setColumnWidth(10, 120); sh.setColumnWidth(11, 120);
  sh.getRange(1, 7, rows.length, 1).setWrap(true);
  if (sh.getFilter()) sh.getFilter().remove();
  sh.getRange(1, 1, rows.length, rows[0].length).createFilter();
  return ss;
}
