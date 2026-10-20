#!/usr/bin/env python3
"""Sign in with ChatGPT を試すスクリプト（Mac で動かす個人用）。

ChatGPT でログインし、atoha の AI 作業（振り分け・まとまり・軸の候補）を
ChatGPT のプラン枠のモデルで実行して、Apple Intelligence の結果と比べる。

  python3 tools/siwc_try.py          # ログイン（初回）→ 試験
  python3 tools/siwc_try.py --logout # 保存したトークンを消す

トークンは ~/.atoha-siwc.json（権限 0600）に保存する。リポジトリには入れない。
手順は https://developers.openai.com/siwc/token-sharing-open-source/ に従う。
"""
import base64, hashlib, http.server, json, os, secrets, sys, threading, time, urllib.parse, urllib.request, uuid, webbrowser

AUTH = "https://auth.openai.com/api/accounts/authorize"
TOKEN = "https://auth.openai.com/api/accounts/oauth/token"
API = "https://api.openai.com/v1"
PORT = 1455
REDIRECT = f"http://127.0.0.1:{PORT}/auth/callback"
SCOPE = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
STORE = os.path.expanduser("~/.atoha-siwc.json")

ERRANDS = ["ゼミの発表スライド作る", "歯医者の予約", "定期券更新", "プリント印刷して持ってく", "Amazonの返品",
           "電気代払う", "サークルの会費集める", "教授にメール返す", "髪切りに行く", "レンタカー返却"]
CONCERNS = ["卒論のテーマ迷う", "もっと英語話せるようになりたい", "あの時の言い方まずかったかも", "一人暮らししてみたいな",
            "就活いつから本気出す？", "バイト辞めようか悩む", "写真をちゃんと撮れるようになりたい", "最近ずっと疲れてる",
            "友達と旅行の計画立てたい", "自分に向いてる仕事ってなんだろう"]


def load():
    try:
        with open(STORE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save(data):
    tmp = STORE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.replace(tmp, STORE)


def post_form(url, fields):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(fields).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def sign_in(state_store):
    host_id = state_store.get("ext_agent_host_id") or f"urn:uuid:{uuid.uuid4()}"
    client_id = state_store.get("client_id", "dynamic_agent_client")
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state, nonce = secrets.token_urlsafe(16), secrets.token_urlsafe(16)
    params = {
        "client_id": client_id, "ext_agent_host_id": host_id, "response_type": "code",
        "redirect_uri": REDIRECT, "scope": SCOPE, "resource": API, "state": state, "nonce": nonce,
        "code_challenge_method": "S256", "code_challenge": challenge,
    }
    if client_id == "dynamic_agent_client":
        params["agent_name_hint"] = "atoha"
    elif state_store.get("id_token"):
        params["id_token_hint"] = state_store["id_token"]

    result = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.path).query))
            if urllib.parse.urlparse(self.path).path != "/auth/callback":
                self.send_response(404); self.end_headers(); return
            result.update(q)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write("atoha: ログインを受け取りました。ターミナルに戻ってください。".encode())

        def log_message(self, *a):
            pass

    server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)  # ブラウザを開く前に待ち受ける
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = AUTH + "?" + urllib.parse.urlencode(params)
    print("ブラウザで ChatGPT にログインしてください。開かない場合は次の URL を開く:\n" + url)
    webbrowser.open(url)
    while not result:
        time.sleep(0.2)
    server.shutdown()

    if result.get("state") != state:
        sys.exit("state が一致しません。中止します。")
    if "error" in result:
        sys.exit(f"ログインできませんでした: {result['error']}")
    issued = result.get("client_id") or (client_id if client_id != "dynamic_agent_client" else None)
    if not issued:
        sys.exit("client_id が返ってきませんでした（登録が完了していません）。")

    tok = post_form(TOKEN, {"grant_type": "authorization_code", "client_id": issued, "code": result["code"],
                            "code_verifier": verifier, "redirect_uri": REDIRECT, "resource": API})
    claims = json.loads(base64.urlsafe_b64decode(tok["id_token"].split(".")[1] + "=="))
    # 試験用なので署名検証は省略し、最低限 nonce と aud を確かめる
    if claims.get("nonce") != nonce or claims.get("aud") not in (issued, [issued]):
        sys.exit("ID トークンの確認に失敗しました。")
    if "chatgpt.tokens.use.direct" not in tok.get("scope", ""):
        sys.exit("プランの利用が許可されませんでした（chatgpt.tokens.use.direct がない）。")
    data = {"ext_agent_host_id": host_id, "client_id": issued, "id_token": tok["id_token"],
            "access_token": tok["access_token"], "refresh_token": tok.get("refresh_token"),
            "expires_at": time.time() + tok.get("expires_in", 3600), "email": claims.get("email")}
    save(data)
    print(f"ログインしました: {claims.get('email', '(メール不明)')}")
    return data


def ensure_token():
    data = load()
    if data.get("access_token") and data.get("expires_at", 0) > time.time() + 60:
        return data
    if data.get("refresh_token"):
        try:
            tok = post_form(TOKEN, {"grant_type": "refresh_token", "client_id": data["client_id"],
                                    "refresh_token": data["refresh_token"], "resource": API})
            data.update(access_token=tok["access_token"], refresh_token=tok.get("refresh_token", data["refresh_token"]),
                        expires_at=time.time() + tok.get("expires_in", 3600))
            save(data)
            return data
        except Exception as e:  # 更新できなければログインし直す
            print("トークンの更新に失敗したので、ログインし直します:", e)
    return sign_in(data)


def models(token):
    req = urllib.request.Request(API + "/models", headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as r:
        body = json.load(r)
    items = body.get("models") or body.get("data") or []
    return [m.get("slug") or m.get("id") for m in items if m.get("visibility", "list") == "list"]


def respond(token, model, instructions, text):
    """Responses API（store=false, stream=true 必須）。完成した文字列を返す。"""
    body = {"model": model, "instructions": instructions, "store": False, "stream": True,
            "input": [{"role": "user", "content": text}]}
    req = urllib.request.Request(API + "/responses", data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    out = []
    with urllib.request.urlopen(req) as r:
        for raw in r:
            line = raw.decode("utf-8").strip()
            if not line.startswith("data:"):
                continue
            ev = json.loads(line[5:].strip() or "{}")
            t = ev.get("type")
            if t == "response.output_text.delta":
                out.append(ev.get("delta", ""))
            elif t == "response.failed":
                raise RuntimeError(ev.get("response", {}).get("error"))
            elif t == "response.completed":
                return "".join(out)
    raise RuntimeError("response.completed が届きませんでした")


def ask_json(token, model, instructions, text):
    s = time.time()
    raw = respond(token, model, instructions + "\nJSON だけを返す。説明は書かない。", text)
    raw = raw.strip().removeprefix("```json").removeprefix("```").removesuffix("```")
    return json.loads(raw), time.time() - s


def main():
    if "--logout" in sys.argv:
        if os.path.exists(STORE):
            os.remove(STORE)
        print("保存したトークンを消しました。")
        return
    data = ensure_token()
    token = data["access_token"]
    available = models(token)
    print("使えるモデル:", ", ".join(available) or "(なし)")
    model = next((m for m in sys.argv[1:] if not m.startswith("-")), None) or (available[0] if available else None)
    if not model:
        sys.exit("使えるモデルがありません。")
    print("使うモデル:", model, "\n")

    # 1. 振り分け（まとめて1回で送る）
    notes = ERRANDS + CONCERNS
    listing = "\n".join(f"{i}: {t}" for i, t in enumerate(notes))
    res, sec = ask_json(token, model,
                        "短いメモを errand（買う・出す・連絡などすぐ済む用事）か concern（アイデア・悩み・考えたいこと）に分ける。"
                        '形式: {"items":[{"index":0,"kind":"errand","theme":"名詞2〜6文字"}]}', listing)
    ok = 0
    for a in res["items"]:
        exp = "errand" if a["index"] < len(ERRANDS) else "concern"
        ok += a["kind"] == exp
        print(f"{'○' if a['kind'] == exp else '×'} {notes[a['index']]} → {a['kind']}  [{a.get('theme', '')}]")
    print(f"振り分け: {ok}/{len(notes)}（{sec:.1f}秒、1回の問い合わせ）\n")

    # 2. まとまり
    listing = "\n".join(f"{i}: {t}" for i, t in enumerate(CONCERNS))
    res, sec = ask_json(token, model,
                        "メモ全体を内容の近さで少数のまとまりに分ける（メモの数の3分の1以下）。同じまとまりには同じ名前。"
                        "名前は日本語の名詞2〜6文字で、個々のメモより広い言葉にする。"
                        '形式: {"items":[{"index":0,"theme":"進路"}]}', listing)
    for a in sorted(res["items"], key=lambda a: a["theme"]):
        print(f"  [{a['theme']}] {CONCERNS[a['index']]}")
    print(f"まとまり: {sec:.1f}秒\n")

    # 3. 軸の候補
    res, sec = ask_json(token, model,
                        "メモ全体から、その人の関心やものごとへの向き合い方の違いを表す「対の軸」を3つ出す。"
                        "両極はどちらも良い悪いのない対等な言葉。気分や体調（不安、疲労、元気など）は使わない。"
                        "どちらの極にもメモがいくつか当てはまる軸にする。メモの単語をそのまま使わない。"
                        "例: 一人で↔人と、作る↔整える、今↔将来、考える↔動く、自分のため↔誰かのため、深める↔広げる。"
                        '形式: {"axes":[{"negative":"一人で","positive":"人と"}]}', "\n".join(CONCERNS))
    for a in res["axes"]:
        print(f"  軸: {a['negative']} ↔ {a['positive']}")
    print(f"軸の候補: {sec:.1f}秒")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        sys.exit(f"HTTP {e.code}: {detail}")
