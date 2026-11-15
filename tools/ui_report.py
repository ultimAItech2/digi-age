"""Create a local, self-contained index of actual Godot verification captures."""
import html
import json
from pathlib import Path

import build_id

root = Path(__file__).resolve().parents[1]
output = root / "builds" / "ui"
captures = sorted(p.name for p in output.glob("*.png"))
report = json.loads((output / "layout-report.json").read_text())
identity = build_id.write({"renderer": report["renderer"], "rendered_checks": report["checks"],
                           "rendered_failures": report["failures"], "screenshots": len(captures)})
cards = "\n".join(f'<a href="{html.escape(name)}" data-name="{html.escape(name)}"><img loading="lazy" src="{html.escape(name)}" alt="{html.escape(name)}"><span>{html.escape(name[:-4])}</span></a>' for name in captures)
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Digital Age · UI verification</title><style>
body{margin:32px;background:#0c1922;color:#e2ebe6;font:16px system-ui}header{max-width:1100px}h1{font-size:28px;color:#6bedcf}p{line-height:1.6}input{padding:12px;background:#12232d;color:white;border:1px solid #8aa5ad;width:min(90%,500px)}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:22px;margin-top:24px}a{color:#adbdc2;text-decoration:none;border:1px solid #8aa5ad;border-radius:6px;overflow:hidden}img{display:block;width:100%}span{display:block;padding:12px}[hidden]{display:none}
</style><header><h1>Digital Age · Production UI verification</h1><p>Actual Godot renders across the desktop resolutions, with the German screens at 1280×720. Click an image to inspect its original pixels. The 1280×720 captures include all three UI scales.</p><p>BUILD_DETAILS</p><input id="filter" placeholder="Filter: 125-manual, 3440, settings…" aria-label="Filter captures"></header><main>CARDS</main><script>document.querySelector('#filter').oninput=e=>document.querySelectorAll('main a').forEach(a=>a.hidden=!a.dataset.name.includes(e.target.value));</script></html>'''
summary = f'{len(captures)} captures · {report["checks"]} rendered checks · {report["failures"]} failures<br>Runtime source: {identity["runtime_source_sha256"]}<br>Renderer: {html.escape(report["renderer"])}'
(output / "index.html").write_text(page.replace("BUILD_DETAILS",summary).replace("CARDS",cards))
print(json.dumps(identity))
