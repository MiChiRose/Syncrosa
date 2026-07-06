# -*- coding: utf-8 -*-
import json
import os
import subprocess
import sys
import tempfile
try:
    import urllib2
except ImportError:
    import urllib.request as urllib2
    import urllib.error
    urllib2.HTTPError = urllib.error.HTTPError
import ssl

try:
    unicode
except NameError:
    unicode = str

def _to_text(value):
    if value is None:
        return u""
    if isinstance(value, unicode):
        return value
    try:
        return value.decode("utf-8", "replace")
    except:
        return unicode(value)

def _to_bytes(value):
    value = _to_text(value)
    if sys.version_info[0] < 3:
        return value.encode("utf-8")
    return value.encode("utf-8")

def _flag_enabled(value):
    if not value:
        return False
    return str(value).strip().lower() in ("1", "yes", "true", "on", "debug")

def _insecure_tls_allowed():
    return _flag_enabled(os.environ.get("SYNCROSA_ALLOW_INSECURE_TLS"))

def _curl_quote(value):
    text = _to_text(value)
    return text.replace("\\", "\\\\").replace('"', '\\"')

def make_request(url, headers_dict, payload_dict=None, timeout_sec=90):
    # In Python 3, URL must be a string, but in Python 2 it can be unicode or bytes.
    if sys.version_info[0] >= 3:
        if isinstance(url, bytes):
            url = url.decode('utf-8')
    else:
        if isinstance(url, unicode):
            url = url.encode('utf-8')
            
    req = urllib2.Request(url)
    req.add_header("User-Agent", "Syncrosa/1.0 (macOS)")
    curl_header_items = [("User-Agent", "Syncrosa/1.0 (macOS)")]
    
    for k, v in headers_dict.items():
        if sys.version_info[0] < 3:
            if isinstance(k, unicode): k = k.encode('utf-8')
            if isinstance(v, unicode): v = v.encode('utf-8')
        else:
            if isinstance(k, bytes): k = k.decode('utf-8')
            if isinstance(v, bytes): v = v.decode('utf-8')
            # Ensure they are str in Python 3
            k = str(k)
            v = str(v)
        req.add_header(k, v)
        curl_header_items.append((k, v))
        
    data = None
    if payload_dict:
        data = json.dumps(payload_dict, ensure_ascii=False).encode('utf-8')
        req.add_header('Content-Type', 'application/json')
        curl_header_items.append(("Content-Type", "application/json"))
        
    def do_curl():
        cmd = ["curl", "-q", "-K"]
        tmp_path = None
        cfg_path = None
        if data:
            tmp_fd, tmp_path = tempfile.mkstemp(suffix=".json")
            try:
                os.chmod(tmp_path, 0o600)
            except:
                pass
            with os.fdopen(tmp_fd, 'wb') as f:
                f.write(data)
        cfg_fd, cfg_path = tempfile.mkstemp(prefix="syncrosa-curl-", suffix=".conf")
        try:
            try:
                os.chmod(cfg_path, 0o600)
            except:
                pass
            lines = [
                'silent',
                'show-error',
                'location',
                'max-time = "{0}"'.format(int(timeout_sec)),
                'url = "{0}"'.format(_curl_quote(url))
            ]
            for hk, hv in curl_header_items:
                lines.append('header = "{0}: {1}"'.format(_curl_quote(hk), _curl_quote(hv)))
            if data:
                lines.append('data-binary = "@{0}"'.format(_curl_quote(tmp_path)))
            cfg_data = ("\n".join(lines) + "\n")
            os.write(cfg_fd, _to_bytes(cfg_data))
            os.close(cfg_fd)
            cfg_fd = None
            cmd.append(cfg_path)
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            out, err = p.communicate()
            if sys.version_info[0] >= 3:
                out = out.decode('utf-8', 'ignore')
                err = err.decode('utf-8', 'ignore')
            if p.returncode == 0:
                return True, out
            return False, "Curl Error: " + err
        except Exception as ce:
            return False, "Curl Exception: " + str(ce)
        finally:
            if cfg_fd is not None:
                try: os.close(cfg_fd)
                except: pass
            if cfg_path:
                try: os.remove(cfg_path)
                except: pass
            if tmp_path:
                try: os.remove(tmp_path)
                except: pass

    try:
        try:
            # First, try modern context with our bundle if it exists
            ctx = ssl.create_default_context()
            base_dir = os.path.dirname(os.path.abspath(__file__))
            ca_path = os.path.join(base_dir, "cacert.pem")
            
            if os.path.exists(ca_path):
                ctx.load_verify_locations(ca_path)
            
            response = urllib2.urlopen(req, data=data, context=ctx, timeout=timeout_sec)
        except (AttributeError, TypeError):
            response = urllib2.urlopen(req, data=data, timeout=timeout_sec)
        except ssl.SSLError:
            if _insecure_tls_allowed() and hasattr(ssl, "create_default_context"):
                try:
                    ctx = ssl.create_default_context()
                    ctx.check_hostname = False
                    ctx.verify_mode = ssl.CERT_NONE
                    response = urllib2.urlopen(req, data=data, context=ctx, timeout=timeout_sec)
                except:
                    response = urllib2.urlopen(req, data=data, timeout=timeout_sec)
            else:
                raise
                
        resp_data = response.read()
        if sys.version_info[0] >= 3:
            resp_data = resp_data.decode('utf-8', 'ignore')
        return True, resp_data
    except urllib2.HTTPError as e:
        err_data = e.read()
        if sys.version_info[0] >= 3:
            err_data = err_data.decode('utf-8', 'ignore')
        if e.code in [401, 403]: 
            return True, err_data
        return False, "HTTP Error: {} - {}".format(e.code, err_data[:4000])
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
        url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent".format(model.strip())
        payload = {"contents": [{"parts": [{"text": "Say 'OK'"}]}], "generationConfig": {"maxOutputTokens": 10}}
        headers = {"x-goog-api-key": api_key.strip()}

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
        url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent".format(model.strip())
        payload = {"contents": [{"parts": [{"text": prompt_text}]}]}
        headers = {"x-goog-api-key": api_key.strip()}

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
