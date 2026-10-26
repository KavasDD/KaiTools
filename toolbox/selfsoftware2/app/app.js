// SPDX-License-Identifier: GPL-3.0-only
'use strict';
// 元器件规格描述生成器 —— 前端逻辑
// 规格描述 = 所有非空字段值按顺序用全角逗号连接（规则来自源表格，已逐条校验）。

const SEP = '，';
const $ = (id) => document.getElementById(id);
let SCHEMA = null;   // 全部分类
let FLAT = [];       // 拍平的物料列表，供搜索
let CUR = null;      // 当前选中的物料 {cat, type}

// 常用分类：按板子 BOM 里出现的频率挑的，会标红、默认展开，但不改变顺序
// （列表一律按表格原顺序，挪位置会让编号跳号，反而不好找）。
// 想改就改这个数组，值是分类编号。
const COMMON = ['1.1', '1.2', '1.3', '2.1', '2.2', '3.1', '3.3', '4', '7', '9'];
const OPEN = new Set(COMMON);   // 展开的分类，常用的默认展开

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
}

async function boot() {
  try {
    const r = await fetch('api/schema');
    if (!r.ok) throw new Error('HTTP ' + r.status);
    SCHEMA = await r.json();
  } catch (e) {
    $('stat').textContent = '加载 schema 失败：' + e.message;
    return;
  }
  SCHEMA.categories.forEach((cat) => {
    cat.types.forEach((t) => FLAT.push({ cat, type: t }));
  });
  $('stat').textContent =
    `${SCHEMA.categories.length} 个分类 / ${FLAT.length} 种物料`;
  showStatus();
  renderList('');
  $('q').addEventListener('input', () => renderList($('q').value));
  $('grab').addEventListener('click', grab);
  $('code').addEventListener('keydown', (e) => { if (e.key === 'Enter') grab(); });
  $('demo').addEventListener('click', () => fillDemo());
  $('clear').addEventListener('click', () => { if (CUR) select(CUR.cat, CUR.type); });
  $('copy').addEventListener('click', copyDesc);
  $('editmode').addEventListener('click', toggleEdit);
  $('ebdone').addEventListener('click', endEdit);

  $('expand').addEventListener('click', () => {
    const allOpen = SCHEMA.categories.every((c) => OPEN.has(c.code));
    OPEN.clear();
    if (!allOpen) SCHEMA.categories.forEach((c) => OPEN.add(c.code));
    $('expand').textContent = allOpen ? '展开全部' : '收起全部';
    renderList($('q').value);
  });
}

function isFav(cat) {
  return COMMON.includes(cat.code);
}

// 控制台原来打印的启动信息，改成显示在网页上：黑窗口用户一般不看，
// 出了问题（用的是旧表、连的是别的端口）在界面上要能直接看出来。
// 发行版根本没有黑窗口，所以退出也得放在这里。
let QUIT_TOKEN = '';

async function showStatus() {
  let s;
  try {
    const r = await fetch('api/status');
    if (!r.ok) throw new Error('HTTP ' + r.status);
    s = await r.json();
  } catch {
    return;                    // 拿不到就算了，不影响主功能
  }
  QUIT_TOKEN = s.token || '';
  const rows = [
    ['运行地址', `http://127.0.0.1:${s.port}/`],
    ['规格表', `${s.source || '未知'}（${s.cats} 个分类 / ${s.types} 种物料）`],
    ['规格表生成时间', s.schemaAt],
    ['运行方式', s.frozen ? '打包版（无命令行窗口）' : '源码运行'],
    ['日志文件', s.log || '（无）'],
    ['配置文件', (s.cfg || '（无）') + (s.cfgOn ? '' : '（还没有，保存后自动建）')],
  ];
  // 配置有毛病要说出来，不然用户只会觉得"改了没生效"
  if (s.cfgErr) rows.push(['配置出错', s.cfgErr]);
  (s.cfgNotes || []).forEach((n) => rows.push(['配置提示', n]));
  $('statbox').innerHTML = rows
    .map(([k, v]) => `<div><span class="sk">${esc(k)}</span>`
      + `<span class="sv">${esc(v)}</span></div>`).join('')
    + '<div class="snote">出错时先看日志文件，里面有详细原因。'
    + '关掉浏览器不会退出程序，要退出请点右上角「退出程序」。</div>';
  const btn = $('statmore');
  btn.hidden = false;
  btn.addEventListener('click', () => {
    const box = $('statbox');
    box.hidden = !box.hidden;
    btn.classList.toggle('on', !box.hidden);
  });
  $('quit').hidden = false;
  $('quit').addEventListener('click', quitApp);
}

// 没有命令行窗口可关，退出只能从网页发指令
async function quitApp() {
  if (!confirm('退出程序？退出后这个页面就打不开了，'
      + '需要重新双击启动。')) return;
  try {
    const r = await fetch('api/quit?token=' + encodeURIComponent(QUIT_TOKEN));
    if (!r.ok) throw new Error('HTTP ' + r.status);
  } catch {
    // 服务端边关边回包，连接被掐是正常的，不当成失败
  }
  document.body.innerHTML = '<div class="byebye">程序已退出，'
    + '可以关掉这个标签页了。<br>需要再用请重新双击启动。</div>';
}

// 分类一律按表格里的原顺序显示。以前把常用的几个挪到最前面，结果列表中间
// 出现"3.2、3.4、3.5"这种跳号，按编号找分类反而要来回翻。
function orderedCats() {
  return SCHEMA.categories;
}

function renderList(q) {
  const kw = q.trim().toLowerCase();
  const ul = $('list');
  ul.innerHTML = '';
  let shown = 0;

  orderedCats().forEach((cat) => {
    const types = cat.types.filter((t) => !kw ||
      (t.name + cat.code + cat.name).toLowerCase().includes(kw));
    if (!types.length) return;
    shown += types.length;
    // 搜索时全部展开，不然要点两下才看到结果
    const open = kw ? true : OPEN.has(cat.code);

    const head = document.createElement('li');
    head.className = 'cat' + (isFav(cat) ? ' fav' : '');
    const hb = document.createElement('button');
    hb.type = 'button';
    hb.className = 'cathead';
    hb.setAttribute('aria-expanded', open ? 'true' : 'false');
    hb.innerHTML = `<span class="tw">${open ? '▾' : '▸'}</span>`
      + `<span class="cname">${esc(cat.code)} ${esc(cat.name)}</span>`
      + `<span class="cnt">${types.length}</span>`;
    hb.addEventListener('click', () => {
      if (OPEN.has(cat.code)) OPEN.delete(cat.code); else OPEN.add(cat.code);
      renderList($('q').value);
    });
    head.appendChild(hb);
    ul.appendChild(head);
    if (!open) return;

    types.forEach((t) => {
      const li = document.createElement('li');
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = t.name;
      b.setAttribute('role', 'option');
      b.setAttribute('aria-selected', CUR && CUR.type === t ? 'true' : 'false');
      if (EDIT) {
        // 改动模式下点名字：既选中它，又就地打开改名框。
        // 只改名不选中的话，右边表单是空的，那一栏的「改选项」就点不到了。
        b.classList.add('rn');
        b.title = '点一下改名称（右边同时会显示它的各栏）';
        b.addEventListener('click', () => {
          select(cat, t);              // 会重画列表，原来那个按钮没了
          const fresh = $('list').querySelector('button[aria-selected="true"]');
          if (!fresh) return;
          inlineRename(fresh, cat, t, (changed) => {
            if (!changed) renderList($('q').value);   // 取消了，把名字放回去
          });
        });
      } else {
        b.addEventListener('click', () => select(cat, t));
      }
      if (t.origName) {
        const tag = document.createElement('span');   // 提示表格里原来叫啥
        tag.className = 'rntag';
        tag.textContent = '改';
        tag.title = '表格里原名：' + t.origName;
        b.appendChild(tag);
      }
      li.appendChild(b);
      if (EDIT) {
        // 用不到的物料可以藏起来，列表太长翻着费劲。藏了还能在配置里放回来。
        const hb = document.createElement('button');
        hb.type = 'button';
        hb.className = 'hidebtn';
        hb.textContent = '藏';
        hb.title = '把「' + t.name + '」从列表里藏起来';
        hb.setAttribute('aria-label', '藏起 ' + t.name);
        hb.addEventListener('click', async () => {
          const arr = cfgPart('hide', cat.code);
          const orig = baseName(t);
          if (!arr.includes(orig)) arr.push(orig);
          if (CUR && CUR.type === t) CUR = null;      // 藏的正是选中那个
          await putCfg(`「${t.name}」已藏起来`);
        });
        li.appendChild(hb);
        li.className = 'rnli';
      }
      ul.appendChild(li);
    });
  });

  if (!shown) {
    ul.innerHTML = '<li class="cat">没有匹配的物料</li>';
  }
}

function select(cat, type, keepMsg) {
  CUR = { cat, type };
  $('empty').hidden = true;
  $('editor').hidden = false;
  $('out').hidden = false;
  $('demo').hidden = false;
  $('clear').hidden = false;
  $('tname').textContent = `${cat.code} ${cat.name} · ${type.name}`;
  $('ref').textContent = type.exampleDesc;
  $('extra').hidden = true;
  if (!keepMsg) note('', '');
  buildForm(type);
  OPEN.add(cat.code);              // 保证选中的那项所在分类是展开的
  renderList($('q').value);
  const sel = $('list').querySelector('[aria-selected="true"]');
  if (sel) sel.scrollIntoView({ block: 'nearest' });
  update();
}

function buildForm(type) {
  const box = $('form');
  box.innerHTML = '';
  type.fields.forEach((f, i) => {
    const id = 'f' + i;
    const name = document.createElement('label');
    name.className = 'name';
    name.htmlFor = id;
    name.innerHTML = f.optional
      ? esc(f.label.replace(/[（(]可选[）)]/, '')) + '<span class="opt">（可选）</span>'
      : esc(f.label);
    if (EDIT) {
      // 栏位名称也能点着改。htmlFor 得摘掉，否则点标题会被浏览器
      // 转给对应的输入框，输入框拿到焦点，标题这儿反而进不了编辑态。
      name.removeAttribute('for');
      name.classList.add('rn');
      name.title = f.origLabel ? '表格里原名：' + f.origLabel : '点一下改栏位名称';
      if (f.origLabel) name.classList.add('changed');
      name.addEventListener('click', () => inlineLabel(name, f));
    }
    box.appendChild(name);

    const wrap = document.createElement('div');
    wrap.className = 'wrap';
    wrap.appendChild(makeInput(f, id));
    const flag = document.createElement('span');
    flag.className = 'flag';
    flag.id = id + '_flag';
    flag.hidden = true;
    wrap.appendChild(flag);
    if (EDIT && f.label !== '物料名称') {
      // 物料名称是固定值（等于物料名），给它选项没意义，改它要用改名
      const ob = document.createElement('button');
      ob.type = 'button';
      ob.className = 'optbtn';
      ob.textContent = '改选项';
      ob.title = '改这一栏的下拉内容';
      ob.addEventListener('click', () => inlineOptions(ob, f));
      wrap.appendChild(ob);
    }
    box.appendChild(wrap);
  });
}

function makeInput(f, id) {
  if (f.kind === 'fixed') {
    const d = document.createElement('div');       // 绿色固定值，不可改
    d.className = 'fixedval';
    d.id = id;
    d.dataset.val = f.fixed;
    d.textContent = f.fixed + '（固定值）';
    // 物料名称这一栏在改动模式下也能点着改，跟左边列表是同一件事
    if (EDIT && f.label === '物料名称' && CUR) {
      const cat = CUR.cat;
      const type = CUR.type;
      d.classList.add('rn');
      d.title = '点一下改名称';
      d.addEventListener('click', () => {
        inlineRename(d, cat, type, (changed) => {
          if (!changed) buildForm(type);
        });
      });
    }
    return d;
  }
  if (f.kind === 'select' && f.options.length) {
    const s = document.createElement('select');
    s.id = id;
    s.appendChild(new Option(f.optional ? '（不填）' : '请选择', ''));
    f.options.forEach((o) => s.appendChild(new Option(o, o)));
    s.addEventListener('change', update);
    return s;
  }
  const inp = document.createElement('input');     // 自由填写
  inp.id = id;
  inp.type = 'text';
  if (f.sample) inp.placeholder = '如 ' + f.sample;
  inp.addEventListener('input', update);
  return inp;
}

function readField(i) {
  const el = $('f' + i);
  if (!el) return '';
  if (el.dataset && el.dataset.val !== undefined) return el.dataset.val;
  return (el.value || '').trim();
}

function setField(i, val) {
  const el = $('f' + i);
  if (!el || el.dataset.val !== undefined) return true;
  if (el.tagName === 'SELECT') {
    const has = [...el.options].some((o) => o.value === val);
    if (!has) el.appendChild(new Option(val + '（表格无此项）', val));
    el.value = val;
    return has;
  }
  el.value = val;
  return true;
}

function update() {
  if (!CUR) return;
  const parts = CUR.type.fields
    .map((f, i) => readField(i))
    .filter((v) => v !== '');
  $('desc').textContent = parts.join(SEP);
}

function fillDemo() {
  CUR.type.fields.forEach((f, i) => {
    if (f.kind === 'fixed') return;
    const v = f.sample || (f.kind === 'select' ? (f.options[0] || '') : '');
    if (v) setField(i, v);
  });
  clearFlags();
  note('已填入表格里的示例值，可直接改。', 'ok');
  update();
}

function clearFlags() {
  CUR.type.fields.forEach((_, i) => {
    const fl = $('f' + i + '_flag');
    if (fl) fl.hidden = true;
  });
}

function note(text, kind) {
  const m = $('msg');
  m.hidden = !text;
  m.textContent = text;
  m.className = 'msg' + (kind ? ' ' + kind : '');
}

async function copyDesc() {
  const text = $('desc').textContent;
  if (!text) return note('还没有内容可复制。', 'err');
  try {
    await navigator.clipboard.writeText(text);
    note('已复制到剪贴板。', 'ok');
  } catch {
    const r = document.createRange();              // 剪贴板被拦时退回选中
    r.selectNodeContents($('desc'));
    getSelection().removeAllRanges();
    getSelection().addRange(r);
    note('浏览器拦了剪贴板，已帮你选中，按 Ctrl+C 复制。', 'err');
  }
}

async function grab() {
  const code = $('code').value.trim();
  if (!code) return note('先填立创编号，例如 C17414。', 'err');
  if (!CUR) return note('先在左边选一种物料，再抓取参数。', 'err');
  const btn = $('grab');
  btn.disabled = true;
  btn.textContent = '抓取中…';
  note('正在向立创商城查询…', '');
  try {
    const url = 'api/lcsc?code=' + encodeURIComponent(code)
      + '&cat=' + encodeURIComponent(CUR.cat.code)
      + '&type=' + encodeURIComponent(CUR.type.name);
    const r = await fetch(url);
    const data = await r.json();
    if (!r.ok) throw new Error(data.error || ('HTTP ' + r.status));
    applyFetched(data);
  } catch (e) {
    note('抓取失败：' + e.message, 'err');
  } finally {
    btn.disabled = false;
    btn.textContent = '抓取参数';
  }
}

function applyFetched(data) {
  clearFlags();
  const fuzzy = new Set(data.fuzzy || []);
  let filled = 0;
  CUR.type.fields.forEach((f, i) => {
    const v = data.values[f.label];
    if (v === undefined || v === '') return;
    const ok = setField(i, v);
    filled += 1;
    const fl = $('f' + i + '_flag');
    if (fl && (!ok || fuzzy.has(f.label))) {
      fl.hidden = false;
      fl.textContent = '请确认';
    }
  });
  update();
  showExtra(data.unmapped || {});
  const info = data.info || {};
  const bits = [`${info.code || ''} ${info.model || ''}`.trim()];
  bits.push(`已填 ${filled} 项`);
  if (fuzzy.size) bits.push(`${fuzzy.size} 项需确认`);
  note(bits.filter(Boolean).join('，') + '。', fuzzy.size ? 'err' : 'ok');
}

function showExtra(unmapped) {
  const keys = Object.keys(unmapped);
  $('extra').hidden = keys.length === 0;
  $('extran').textContent = keys.length ? `（${keys.length} 项）` : '';
  $('extrabody').innerHTML = keys
    .map((k) => `${esc(k)}：${esc(unmapped[k])}`)
    .join('<br>');
}

// ===== 改名称 / 改选项（就地改，不用弹窗）=====
// 名称和选项本来是表格定死的，改一次要动 Excel 再重新生成，太重。
// 现在存进 config.json：点开关进入改动模式，左边物料名直接点着改，
// 右边每个字段后面多一个「改选项」。表格重新生成也不会把改动冲掉。
let EDIT = false;     // 是否处于改动模式
let CFG = null;       // 当前配置，结构见 app/config.py

async function toggleEdit() {
  if (EDIT) return endEdit();
  if (!CFG) {
    try {
      const r = await fetch('api/config');
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const d = await r.json();
      if (!d || typeof d.config !== 'object') throw new Error('返回内容不对');
      CFG = d.config;                 // 拿到才认账，失败保持 null 可重试
      ebMsg(d.path ? '改动存到 ' + d.path : '', '');
      if (d.err) ebMsg(d.err, 'bad');
    } catch (e) {
      ebMsg('配置读不出来：' + e.message + '，可以再点一次', 'bad');
      $('editbar').hidden = false;
      return;
    }
  }
  EDIT = true;
  $('editmode').classList.add('on');
  $('editmode').setAttribute('aria-pressed', 'true');
  $('editbar').hidden = false;
  document.body.classList.add('editing');
  renderList($('q').value);
  if (CUR) buildForm(CUR.type);       // 重画表单，带上「改选项」
}

function endEdit() {
  EDIT = false;
  $('editmode').classList.remove('on');
  $('editmode').setAttribute('aria-pressed', 'false');
  $('editbar').hidden = true;
  document.body.classList.remove('editing');
  renderList($('q').value);
  if (CUR) buildForm(CUR.type);
}

function ebMsg(text, cls) {
  const el = $('ebmsg');
  el.textContent = text;
  el.className = cls || '';
}

// 存配置。每改一处就存一次——改完还要记得点保存，很容易白改一场。
async function putCfg(desc) {
  ebMsg('正在保存…', '');
  let d;
  try {
    const r = await fetch('api/config?token=' + encodeURIComponent(QUIT_TOKEN), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(CFG),
    });
    d = await r.json();
    if (!r.ok) throw new Error(d.error || 'HTTP ' + r.status);
  } catch (e) {
    ebMsg('保存失败：' + e.message, 'bad');
    return false;
  }
  await reload();
  ebMsg((desc || '已保存') + (d.notes && d.notes.length
    ? '，但：' + d.notes.join('；') : '') + `（共 ${d.types} 种物料）`,
    d.notes && d.notes.length ? 'bad' : 'ok');
  return true;
}

// 物料在表格里的原名。改过名的用 origName，配置一律按原名记，
// 这样改第二次不会在配置里堆出一串中间名字。
function baseName(t) {
  return t.origName || t.name;
}

function cfgPart(key, code) {
  if (!CFG[key]) CFG[key] = {};
  if (!CFG[key][code]) CFG[key][code] = key === 'hide' ? [] : {};
  return CFG[key][code];
}

// 把一个显示名字的地方变成输入框，改完回调。左边列表和表单里都用它。
function inlineRename(el, cat, type, done) {
  if (el.dataset.editing) return;
  el.dataset.editing = '1';
  const before = type.name;
  const inp = document.createElement('input');
  inp.type = 'text';
  inp.className = 'renameinp';
  inp.value = before;
  inp.setAttribute('aria-label', '改物料名称');
  el.textContent = '';
  el.appendChild(inp);
  inp.focus();
  inp.select();

  let closed = false;
  const finish = async (ok) => {
    if (closed) return;
    closed = true;
    delete el.dataset.editing;
    const val = (inp.value || '').trim();
    if (!ok || !val || val === before) return done(false);
    const ren = cfgPart('rename', cat.code);
    const orig = baseName(type);
    if (val === orig) delete ren[orig];   // 改回原名就把这条删掉
    else ren[orig] = val;
    if (!Object.keys(ren).length) delete CFG.rename[cat.code];
    const okSaved = await putCfg(`「${before}」已改成「${val}」`);
    done(okSaved);
  };
  inp.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); finish(true); }
    if (e.key === 'Escape') { e.preventDefault(); finish(false); }
  });
  inp.addEventListener('blur', () => finish(true));
  // 别让点击冒泡到外层按钮，否则一点就变成"选中物料"把输入框冲掉
  inp.addEventListener('click', (e) => e.stopPropagation());
}

// 栏位在表格里的原名。改过的看 origLabel，配置一律按原名记。
function baseLabel(f) {
  return f.origLabel || f.label;
}

// 改栏位名称（左边那一列的标题）。默认整个分类一起改——表格里同一分类下
// 栏位标题本来就一致，一个个改太累；勾上「只改这一种」就只管当前这种物料。
function inlineLabel(el, field) {
  if (el.dataset.editing) return;
  el.dataset.editing = '1';
  const before = field.label;
  const html = el.innerHTML;
  el.innerHTML = '';
  el.classList.add('editing');

  const inp = document.createElement('input');
  inp.type = 'text';
  inp.className = 'renameinp';
  inp.value = before;
  inp.setAttribute('aria-label', '改栏位名称');
  const only = document.createElement('label');
  only.className = 'onlyone';
  const cb = document.createElement('input');
  cb.type = 'checkbox';
  only.appendChild(cb);
  only.appendChild(document.createTextNode('只改这一种'));
  only.title = '不勾：' + CUR.cat.code + ' 这个分类下的物料都改；勾上：只改「'
    + CUR.type.name + '」';
  el.appendChild(inp);
  el.appendChild(only);
  inp.focus();
  inp.select();

  let closed = false;
  const finish = async (ok) => {
    if (closed) return;
    closed = true;
    delete el.dataset.editing;
    el.classList.remove('editing');
    const val = (inp.value || '').trim();
    if (!ok || !val || val === before) { el.innerHTML = html; return; }
    const per = cfgPart('labels', CUR.cat.code);
    const scope = cb.checked ? baseName(CUR.type) : '*';
    const src = baseLabel(field);
    if (!per[scope]) per[scope] = {};
    if (val === src) delete per[scope][src];     // 改回原名就把这条删掉
    else per[scope][src] = val;
    if (!Object.keys(per[scope]).length) delete per[scope];
    if (!Object.keys(per).length) delete CFG.labels[CUR.cat.code];
    await putCfg(`栏位「${before}」已改成「${val}」`
      + (cb.checked ? '（只这一种）' : `（整个 ${CUR.cat.code}）`));
  };
  inp.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); finish(true); }
    if (e.key === 'Escape') { e.preventDefault(); finish(false); }
  });
  // 勾选框本身也在这个标签里，点它会触发 blur，不能当成"改完了"
  inp.addEventListener('blur', () => setTimeout(() => {
    if (el.contains(document.activeElement)) return;
    finish(true);
  }, 0));
  el.addEventListener('click', (e) => e.stopPropagation());
}

// 改某个字段的下拉选项。就地展开一个输入框，逗号分隔。
function inlineOptions(anchor, field) {
  const box = anchor.parentNode.querySelector('.optedit');
  if (box) { box.remove(); return; }
  const wrap = document.createElement('div');
  wrap.className = 'optedit';
  const inp = document.createElement('input');
  inp.type = 'text';
  inp.value = field.options.join('，');
  inp.placeholder = '逗号分隔，留空表示不用下拉、改成手填';
  inp.setAttribute('aria-label', field.label + ' 的选项');
  const ok = document.createElement('button');
  ok.type = 'button';
  ok.className = 'chip';
  ok.textContent = '存';
  const tip = document.createElement('span');
  tip.className = 'opttip';
  tip.textContent = field.options.length
    ? `现有 ${field.options.length} 项` : '现在没有下拉';
  wrap.appendChild(inp);
  wrap.appendChild(ok);
  // 改坏了要能退回表格里原来的选项，否则清空之后就没法恢复了
  const per0 = (CFG.options || {})[CUR.cat.code] || {};
  const mine = per0[baseName(CUR.type)] || {};
  if (Object.prototype.hasOwnProperty.call(mine, baseLabel(field))) {
    const undo = document.createElement('button');
    undo.type = 'button';
    undo.className = 'chip';
    undo.textContent = '还原';
    undo.title = '删掉这一栏的改动，用回表格里的选项';
    undo.addEventListener('click', async () => {
      delete mine[baseLabel(field)];
      if (!Object.keys(mine).length) delete per0[baseName(CUR.type)];
      if (!Object.keys(per0).length) delete CFG.options[CUR.cat.code];
      await putCfg(`「${field.label}」已还原`);
    });
    wrap.appendChild(undo);
  }
  wrap.appendChild(tip);
  anchor.parentNode.appendChild(wrap);
  inp.focus();

  const save = async () => {
    const list = (inp.value || '').split(/[，,]/)
      .map((s) => s.trim()).filter(Boolean);
    const per = cfgPart('options', CUR.cat.code);
    const orig = baseName(CUR.type);
    if (!per[orig]) per[orig] = {};
    per[orig][baseLabel(field)] = list;   // 按原栏位名记，改了标题也不脱钩
    await putCfg(list.length
      ? `「${field.label}」改成 ${list.length} 个选项`
      : `「${field.label}」改成手填`);
  };
  ok.addEventListener('click', save);
  inp.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); save(); }
    if (e.key === 'Escape') { e.preventDefault(); wrap.remove(); }
  });
}

async function reload() {
  // 记原名而不只记显示名：改过一次名的物料，再改一次时显示名已经不是
  // 表格里那个了，只按显示名找会找不回来，选中就丢了。
  const keep = CUR
    ? { code: CUR.cat.code, name: CUR.type.name, orig: baseName(CUR.type) }
    : null;
  const r = await fetch('api/schema');
  SCHEMA = await r.json();
  FLAT = [];
  SCHEMA.categories.forEach((cat) => {
    cat.types.forEach((t) => FLAT.push({ cat, type: t }));
  });
  $('stat').textContent =
    `${SCHEMA.categories.length} 个分类 / ${FLAT.length} 种物料`;
  renderList($('q').value);
  const hit = keep && FLAT.find((x) => x.cat.code === keep.code
    && (baseName(x.type) === keep.orig || x.type.name === keep.name));
  if (hit) { CUR = { cat: hit.cat, type: hit.type }; select(hit.cat, hit.type); return; }
  // 选中那个被藏了或没了：右边不能继续留着它的表单，不然改的是个不存在的物料
  CUR = null;
  $('editor').hidden = true;
  $('out').hidden = true;
  $('demo').hidden = true;
  $('clear').hidden = true;
  $('empty').hidden = false;
}
boot();
