# -*- coding: utf-8 -*-
import json
import os
import subprocess
import urllib2
import ssl

def make_request(url, headers_dict, payload_dict=None, timeout_sec=90):
    req = urllib2.Request(url)
    req.add_header("User-Agent", "iTunesGeniusAI/1.0 (macOS)")
    
    curl_headers = ["-H", "User-Agent: iTunesGeniusAI/1.0 (macOS)"]
    
    for k, v in headers_dict.items():
        if isinstance(k, unicode): k = k.encode('utf-8')
        if isinstance(v, unicode): v = v.encode('utf-8')
        req.add_header(k, v)
        curl_headers.extend(["-H", "{}: {}".format(k, v)])
        
    data = None
    if payload_dict:
        data = json.dumps(payload_dict, ensure_ascii=False).encode('utf-8')
        req.add_header('Content-Type', 'application/json')
        curl_headers.extend(["-H", "Content-Type: application/json"])
        
    def do_curl():
        cmd = ["curl", "-sSL", "-m", str(timeout_sec)] + curl_headers
        tmp_path = None
        if data:
            import tempfile
            tmp_fd, tmp_path = tempfile.mkstemp(suffix=".json")
            with os.fdopen(tmp_fd, 'wb') as f:
                f.write(data)
            cmd.extend(["-d", "@" + tmp_path])
            
        cmd.append(url)
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            out, err = p.communicate()
            if tmp_path:
                try: os.remove(tmp_path)
                except: pass
            if p.returncode == 0:
                return True, out
            return False, "Curl Error: " + err
        except Exception as ce:
            if tmp_path:
                try: os.remove(tmp_path)
                except: pass
            return False, "Curl Exception: " + str(ce)

    try:
        try:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            response = urllib2.urlopen(req, data=data, context=ctx, timeout=timeout_sec)
        except AttributeError:
            response = urllib2.urlopen(req, data=data, timeout=timeout_sec)
        return True, response.read()
    except urllib2.HTTPError as e:
        if e.code in [401, 403]: 
            return True, e.read()
        return False, "HTTP Error: {} - {}".format(e.code, e.read()[:100])
    except Exception as e:
        err_str = str(e).lower()
        if "ssl" in err_str or "handshake" in err_str or "errno 1" in err_str or "socket error" in err_str or "eof" in err_str:
            return do_curl()
        return False, "Network Error: " + str(e)

def test_api_key(provider, api_key, model):
    if provider == "Groq":
        url = "https://api.groq.com/openai/v1/chat/completions"
        payload = {"model": model.strip(), "messages": [{"role": "user", "content": "Say 'OK'"}], "max_tokens": 10}
        headers = {"Authorization": "Bearer " + api_key.strip()}
    elif provider == "OpenRouter":
        url = "https://openrouter.ai/api/v1/chat/completions"
        payload = {"model": model.strip(), "messages": [{"role": "user", "content": "Say 'OK'"}], "max_tokens": 10}
        headers = {
            "Authorization": "Bearer " + api_key.strip(),
            "HTTP-Referer": "https://github.com/YuraMenschikov/iTunesGeniusAI",
            "X-Title": "iTunesGeniusAI"
        }
    else:
        url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}".format(model.strip(), api_key.strip())
        payload = {"contents": [{"parts": [{"text": "Say 'OK'"}]}], "generationConfig": {"maxOutputTokens": 10}}
        headers = {}

    ok, result = make_request(url, headers, payload, timeout_sec=120)
    if not ok: return False, result

    try:
        resp = json.loads(result)
        if provider == "Groq" or provider == "OpenRouter":
            if "choices" in resp: return True, "OK"
            err_msg = resp.get("error", {}).get("message", "Unknown Error")
            return False, err_msg + "\n\nFULL RESPONSE:\n" + result
        else:
            if "candidates" in resp: return True, "OK"
            err_msg = resp.get("error", {}).get("message", "Unknown Gemini Error")
            return False, err_msg + "\n\nFULL RESPONSE:\n" + result
    except Exception as e:
        return False, "Parse Error: " + str(e) + "\nRaw: " + result

def call_ai_for_playlist(provider, api_key, model, prompt_text):
    if provider == "Groq":
        url = "https://api.groq.com/openai/v1/chat/completions"
        payload = {
            "model": model.strip(), 
            "messages": [
                {"role": "system", "content": "You are a strict data API. You MUST output ONLY a valid JSON array of strings. You must NEVER output conversational text, introductions, or markdown. Output exactly what is requested and nothing else."},
                {"role": "user", "content": prompt_text}
            ], 
            "temperature": 0.3
        }
        headers = {"Authorization": "Bearer " + api_key.strip()}
    elif provider == "OpenRouter":
        url = "https://openrouter.ai/api/v1/chat/completions"
        payload = {
            "model": model.strip(), 
            "messages": [
                {"role": "system", "content": "You are a strict data API. You MUST output ONLY a valid JSON array of strings. You must NEVER output conversational text, introductions, or markdown. Output exactly what is requested and nothing else."},
                {"role": "user", "content": prompt_text}
            ], 
            "temperature": 0.3
        }
        headers = {
            "Authorization": "Bearer " + api_key.strip(),
            "HTTP-Referer": "https://github.com/YuraMenschikov/iTunesGeniusAI",
            "X-Title": "iTunesGeniusAI"
        }
    else:
        url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}".format(model.strip(), api_key.strip())
        payload = {"contents": [{"parts": [{"text": prompt_text}]}]}
        headers = {}

    ok, result = make_request(url, headers, payload, timeout_sec=120)
    if not ok: return False, result
    
    try:
        resp = json.loads(result)
        if provider == "Groq" or provider == "OpenRouter":
            text = resp["choices"][0]["message"]["content"]
        else:
            text = resp["candidates"][0]["content"]["parts"][0]["text"]
        return True, text
    except Exception as e:
        return False, "Failed to parse AI response: " + str(e) + "\nRaw: " + result
