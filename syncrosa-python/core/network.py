# -*- coding: utf-8 -*-
import json
import os
import subprocess
import urllib2
import ssl

def make_request(url, headers_dict, payload_dict=None, timeout_sec=90):
    req = urllib2.Request(url)
    req.add_header("User-Agent", "Syncrosa/1.0 (macOS)")
    
    curl_headers = ["-H", "User-Agent: Syncrosa/1.0 (macOS)"]
    
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
        # --- MATCHING WORKING DIAGNOSTIC TEST ---
        try:
            # First, try modern context with our bundle if it exists
            ctx = ssl.create_default_context()
            base_dir = os.path.dirname(os.path.abspath(__file__))
            ca_path = os.path.join(base_dir, "cacert.pem")
            
            if os.path.exists(ca_path):
                ctx.load_verify_locations(ca_path)
            else:
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
            
            response = urllib2.urlopen(req, data=data, context=ctx, timeout=timeout_sec)
        except (AttributeError, TypeError, ssl.SSLError):
            # Fallback to exact Method 2 from diag_network.py
            try:
                # Some Python versions support context but fail with our bundle
                ctx = ssl.create_default_context()
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
                response = urllib2.urlopen(req, data=data, context=ctx, timeout=timeout_sec)
            except:
                # Final fallback: legacy urllib2
                response = urllib2.urlopen(req, data=data, timeout=timeout_sec)
                
        return True, response.read()
    except urllib2.HTTPError as e:
        if e.code in [401, 403]: 
            return True, e.read()
        return False, "HTTP Error: {} - {}".format(e.code, e.read()[:4000])
    except Exception as e:
        # Only fallback to curl if it's an SSL/Protocol error
        err_str = str(e).lower()
        if any(kw in err_str for kw in ["ssl", "handshake", "errno 1", "socket error", "eof", "failed"]):
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
            "HTTP-Referer": "https://github.com/YuraMenschikov/Syncrosa",
            "X-Title": "Syncrosa"
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
    print("\n--- AI REQUEST START ---")
    print("Provider: {}".format(provider))
    print("Model: {}".format(model))
    
    payload_size = len(prompt_text.encode('utf-8'))
    print("Payload Size: {:.2f} KB".format(payload_size / 1024.0))

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
            "HTTP-Referer": "https://github.com/YuraMenschikov/Syncrosa",
            "X-Title": "Syncrosa"
        }
    else:
        url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}".format(model.strip(), api_key.strip())
        payload = {"contents": [{"parts": [{"text": prompt_text}]}]}
        headers = {}

    print("Sending request... (Timeout: 120s)")
    ok, result = make_request(url, headers, payload, timeout_sec=120)
    
    if not ok:
        print("REQUEST FAILED: {}".format(result))
        return False, result
    
    print("Response received ({:.2f} KB)".format(len(result) / 1024.0))
    
    try:
        resp = json.loads(result)
        if provider == "Groq" or provider == "OpenRouter":
            text = resp["choices"][0]["message"]["content"]
        else:
            text = resp["candidates"][0]["content"]["parts"][0]["text"]
        print("--- AI REQUEST SUCCESS ---\n")
        return True, text
    except Exception as e:
        print("PARSE ERROR: {}".format(str(e)))
        return False, "Failed to parse AI response: " + str(e) + "\nRaw: " + result
