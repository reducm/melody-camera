#!/usr/bin/env python3
"""从本目录的内容源生成评审稿、页面规格和 Mermaid；仅 Python 标准库。"""
import argparse
import base64
import copy
import html
import json
import re
from pathlib import Path

BASE = Path(__file__).resolve().parent


def inline(value):
    value = html.escape(value)
    value = re.sub(r'`([^`]+)`', r'<code>\1</code>', value)
    value = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', value)
    return value


def markdown_html(text):
    """本稿使用的有限 Markdown 子集；不执行嵌入 HTML。"""
    out, paragraph, table = [], [], []

    def flush():
        if paragraph:
            out.append('<p>' + inline(' '.join(paragraph)) + '</p>')
            paragraph.clear()
        if table:
            rows = [[c.strip() for c in line.strip('|').split('|')] for line in table]
            out.append('<div class="table-wrap"><table><thead><tr>' + ''.join('<th>' + inline(c) + '</th>' for c in rows[0]) + '</tr></thead><tbody>')
            for row in rows[2:]:
                out.append('<tr>' + ''.join('<td>' + inline(c) + '</td>' for c in row) + '</tr>')
            out.append('</tbody></table></div>')
            table.clear()

    for line in text.splitlines():
        if line.startswith('|'):
            if paragraph:
                flush()
            table.append(line)
        elif line.startswith('#'):
            flush()
            level = min(len(line) - len(line.lstrip('#')), 4)
            out.append(f'<h{level}>{inline(line.lstrip("# "))}</h{level}>')
        elif not line.strip():
            flush()
        else:
            if table:
                flush()
            paragraph.append(line)
    flush()
    return '\n'.join(out)


def build(inline_output=None):
    data = json.loads((BASE / 'review-data.json').read_text())
    pages, future = data['pages'], data['future']
    all_entities = {p['id']: p for p in pages + future}
    assert len(all_entities) == len(pages) + len(future), '编号重复'
    for p in pages:
        assert (BASE.parent.parent / p['source']).exists(), p['source']
        if p.get('media'):
            for key in ['src', 'thumbnail']:
                assert (BASE / p['media'][key]).exists(), p['media'][key]
        for label, target in p['actions']:
            assert target in all_entities, (p['id'], label, target)

    spec = ['# Melody 相机页面规格', '', f'版本 v{data["version"]} · {data["date"]}。由 review-data.json 生成。需求正文见 [产品需求](产品需求.md)。编号用于持续讨论，不表示每项都是独立路由。', '', '| 编号 | 页面或区域 | 形态 | 状态 |', '|---|---|---|---|']
    spec += [f'| {p["id"]} | [{p["title"]}](#{p["id"].lower()}) | {p["kind"]} | {p["status"]} |' for p in pages]
    for p in pages:
        spec += ['', f'<a id="{p["id"].lower()}"></a>', f'## {p["id"]} {p["title"]}', '', f'**{p["kind"]} · {p["status"]}**', '', p['purpose'], '', '**入口**：' + p['entry'], '', '**页面结构**', '']
        spec += [f'{i+1}. {v}' for i, v in enumerate(p['layout'])]
        spec += ['', '**动作与去向**', '', '| 用户动作或结果 | 去向 |', '|---|---|']
        spec += [f'| {label} | [{target} {all_entities[target]["title"]}](#{target.lower()}) |' for label, target in p['actions']]
        for key, title in [('states', '状态与异常'), ('rules', '行为规则')]:
            spec += ['', f'**{title}**', ''] + ['- ' + value for value in p[key]]
        for key, title in [('data', '数据'), ('evidence', '已有证据与待验'), ('acceptance', '验收条件'), ('discussion', '待讨论')]:
            spec += ['', f'**{title}**：' + p[key]]
        spec += ['', f'**源码入口**：[{Path(p["source"]).name}](../../{p["source"]})']
        if p.get('media'):
            spec += ['', f'**界面图**：[{p["media"]["alt"]}]({p["media"]["src"]})。{p["media"]["caption"]}']
    spec += ['', '## 后续规划单元', '']
    for p in future:
        spec += [f'<a id="{p["id"].lower()}"></a>', f'### {p["id"]} {p["title"]}', '', p['status'] + '。' + p['text'], '']
    (BASE / '页面规格.md').write_text('\n'.join(spec).rstrip() + '\n')

    flows = ['# Melody 相机页面流程图', '', f'版本 v{data["version"]} · {data["date"]}。由 review-data.json 生成。截图节点见 [交互评审稿](评审稿.html)，图片来源见 [截图说明](assets/README.md)。实线表示已有交互关系；规划单独用虚线。P 编号可在 [页面规格](页面规格.md) 定位。系统返回均回原入口，图中的项目/相机出口是相应场景的示例。', '']
    for flow in data['flows']:
        keys = {n[0] for n in flow['nodes']}
        assert len(keys) == len(flow['nodes']), flow['id']
        lines = ['flowchart TD']
        for key, pid, _, _ in flow['nodes']:
            assert pid in all_entities, pid
            name = all_entities[pid]['title']
            lines.append(f'    {key}["{pid} {name}"]')
        for start, end, label in flow['edges']:
            assert start in keys and end in keys
            arrow = f'-. "{label}" .->' if flow.get('planned') else f'-->|"{label}"|'
            lines.append(f'    {start} {arrow} {end}')
        flows += [f'## {flow["id"]} {flow["title"]}', '', flow['note'], '', '```mermaid', '\n'.join(lines), '```', '']
    (BASE / '页面流程图.md').write_text('\n'.join(flows))

    fragment = (BASE / 'review-template.html').read_text()
    fragment = fragment.replace('__REVIEW_DATA__', json.dumps(data, ensure_ascii=False).replace('</', '<\\/'))
    fragment = fragment.replace('__PRD_HTML__', markdown_html((BASE / '产品需求.md').read_text()))
    standalone = '<!doctype html>\n<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark"><title>Melody 相机页面与流程评审</title><style>body{margin:0;padding:24px;background:light-dark(#eef1ec,#101416);color-scheme:light dark}#melody-prd-review{max-width:1120px;margin:auto}@media(max-width:600px){body{padding:6px}}</style></head><body>\n' + fragment + '\n</body></html>\n'
    (BASE / '评审稿.html').write_text(standalone)
    if inline_output:
        inline_output = Path(inline_output).resolve()
        inline_output.parent.mkdir(parents=True, exist_ok=True)
        inline_data = copy.deepcopy(data)
        inline_data['embeddedAssets'] = {}
        for p in inline_data['pages']:
            if p.get('media'):
                preview = p['media']['thumbnail']
                inline_data['embeddedAssets'][preview] = 'data:image/jpeg;base64,' + base64.b64encode((BASE / preview).read_bytes()).decode()
        inline_fragment = (BASE / 'review-template.html').read_text().replace('__REVIEW_DATA__', json.dumps(inline_data, ensure_ascii=False).replace('</', '<\\/'))
        inline_fragment = inline_fragment.replace('__PRD_HTML__', markdown_html((BASE / '产品需求.md').read_text()))
        assert len(inline_fragment.encode()) < 1_000_000, '内嵌预览超过 1 MB，请降低预览副本的文件大小；原始截图不要覆盖。'
        inline_output.write_text(inline_fragment)
    print(f'已生成：{len(pages)} 个页面单元、{len(future)} 个规划模块、{len(data["flows"])} 张流程图。')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--inline-output', type=Path, help='可选：同一评审稿的聊天内嵌版本绝对路径')
    args = parser.parse_args()
    build(args.inline_output)
