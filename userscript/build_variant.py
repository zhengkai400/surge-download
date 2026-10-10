from pathlib import Path
import re
root=Path(__file__).resolve().parent
source=root.parent/'.build/linkswift-reference/LinkSwift.user.js'
s=source.read_text(encoding='utf-8-sig')
s=s.replace('// @name              LinkSwift','// @name              LinkSwift 疾风文件夹版').replace('// @version           1.1.3','// @version           1.1.3-surge.1')
s=re.sub(r'^// @(?:updateURL|downloadURL).*\n','',s,flags=re.M)
# Separate identity preserves the original script/settings for rollback.
s=s.replace('// @namespace         github.com/hmjz100','// @namespace         local.surge.linkswift.folders')
s='// Modified 2026-10-10: recursive Quark folders and relative output paths.\n'+s
start=s.index('\t\tasync getLink() {',s.index('config.$quark.mount.home'))
end=s.index('\n\t\tgetSelectedList()',start)
part=s[start:end]
old='if (selectList.every(item => !item.file)) return message.error("提示：<br/>请打开文件夹后再勾选文件~");'
assert old in part
replacement='''try {
                const pwd = location.pathname.match(/^\\/(?:s|share)\\/([a-zA-Z0-9]+)/)?.[1];
                selectList = await surgeExpandFolders(selectList, async (folder, page, stoken) => {
                    const share = temp.page === "share";
                    if (share && (!pwd || !stoken)) throw Error("缺少分享访问凭据，请刷新分享页面");
                    const params = new URLSearchParams({pr:"ucpro", fr:"pc", pdir_fid:folder.fid, _page:String(page), _size:"100", _fetch_total:"1", _sort:"file_type:asc,file_name:asc"});
                    if (share) {params.set("pwd_id",pwd); params.set("stoken",stoken);}
                    const endpoint = share ? "share/sharepage/detail" : "file/sort";
                    await base.sleep(250);
                    const res = await base.get("https://drive-pc.quark.cn/1/clouddrive/"+endpoint+"?"+params);
                    if (res?.code !== 0 || !Array.isArray(res?.data?.list)) throw Error("读取目录失败，代码："+String(res?.code ?? "未知"));
                    return res.data.list;
                });
                if (!selectList.length) return message.error("选中的目录没有文件");
                if (!window.confirm("已展开 "+selectList.length+" 个文件。继续获取链接？目录路径仅在疾风 Aria2 推送中保留。")) return;
            } catch (e) { return message.error(String(e.message).replace(/[<>&]/g, "")); }
            const surgePaths = new Map(selectList.map(v => [v.fid,v.surgePath]));'''
part=part.replace(old,replacement)
part=part.replace('data.push(...res.data);','data.push(...res.data.map(v => ({...v, file_name:surgePaths.get(v.fid) || v.file_name})));')
s=s[:start]+part+s[end:]
# Function declaration is hoisted; shared existing dialog handles preview and per-file push results.
s+='\n'+(root/'folder-core.js').read_text()
(root/'LinkSwift-Surge-Folders.user.js').write_text(s)
