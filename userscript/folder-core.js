// Surge folder extension, 2026-10-10, AGPL-3.0-or-later.
// Pure traversal; credentials and networking are supplied by the existing script.
async function surgeExpandFolders(selected, listPage, progress = () => {}) {
  const files = [], seen = new Set(), paths = new Set();
  const safe = name => {
    if (typeof name !== 'string' || !name || name === '.' || name === '..' || /[\\/\x00-\x1f]/.test(name)) throw Error('目录或文件名含非法路径字符');
    return name;
  };
  async function walk(items, parents, token) {
    if (parents.length > 32) throw Error('目录超过 32 层');
    for (const item of items) {
      if (!item.fid) throw Error('目录接口缺少文件 ID');
      if (seen.has(item.fid)) continue;
      seen.add(item.fid);
      if (seen.size > 20000) throw Error('超过单次 20000 项限制，请分批选择');
      const path = [...parents, safe(item.file_name)];
      const stoken = item.stoken || token;
      if (item.file === true || (item.file !== false && item.dir === false)) {
        const relative = path.join('/');
        if (paths.has(relative)) throw Error('出现重名路径，请分批下载');
        paths.add(relative);
        files.push({...item, file:true, stoken, surgePath:relative});
        progress(files.length);
      } else {
        const pages = new Set();
        for (let page = 1; ; page++) {
          if (page > 1000) throw Error('目录分页超过限制');
          const children = await listPage(item, page, stoken);
          if (!Array.isArray(children)) throw Error('目录接口返回格式异常');
          if (!children.length) break;
          const signature = children.map(v => v.fid).join(',');
          if (pages.has(signature)) throw Error('目录分页重复，已停止以免遗漏');
          pages.add(signature);
          await walk(children, path, stoken);
          // Request until empty, rather than trusting a server page-size cap.
        }
      }
    }
  }
  await walk(selected, [], '');
  return files;
}
if (typeof module !== 'undefined') module.exports = {surgeExpandFolders};
