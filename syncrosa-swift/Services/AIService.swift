import Foundation

class AIService {
    static let shared = AIService()
    
    // Persistent cache for models
    var cachedOpenRouterModels: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: "cached_openrouter_models") ?? ["google/gemini-2.0-flash-exp:free", "meta-llama/llama-3.1-8b-instruct:free", "mistralai/mistral-7b-instruct:free"]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "cached_openrouter_models")
        }
    }
    
    func fetchOpenRouterModels(completion: @escaping ([String]?) -> Void) {
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataArray = json["data"] as? [[String: Any]] {
                    let freeModels = dataArray.compactMap { m -> String? in
                        if let id = m["id"] as? String, id.contains(":free") {
                            return id
                        }
                        return nil
                    }.sorted()
                    
                    if !freeModels.isEmpty {
                        self.cachedOpenRouterModels = freeModels
                    }
                    completion(freeModels)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    func validateAPIKey(provider: String, apiKey: String, model: String, completion: @escaping (Bool, String) -> Void) {
        guard !apiKey.isEmpty else {
            completion(false, "API Key is empty")
            return
        }
        
        let url: URL
        var request: URLRequest
        
        if provider == "Groq" {
            url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
            request = URLRequest(url: url)
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": "Say 'OK'"]],
                "max_tokens": 10
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else if provider == "OpenRouter" {
            url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            request = URLRequest(url: url)
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": "Say 'OK'"]],
                "max_tokens": 10
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            // Gemini
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "contents": [["parts": [["text": "Say 'OK'"]]]],
                "generationConfig": ["maxOutputTokens": 10]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            guard let data = data else {
                completion(false, "No data received")
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if provider == "Gemini" {
                    if json?["candidates"] != nil { completion(true, "OK") }
                    else { completion(false, "Invalid Gemini Response") }
                } else {
                    if json?["choices"] != nil { completion(true, "OK") }
                    else { completion(false, "Invalid Provider Response") }
                }
            } catch {
                completion(false, "Parse Error")
            }
        }.resume()
    }
    
    func generatePlaylistSuggestions(provider: String, apiKey: String, model: String, prompt: String, count: Int, librarySample: [String], completion: @escaping ([String]?) -> Void) {
        let url: URL
        var request: URLRequest
        
        let libraryText = librarySample.joined(separator: "\\n")
        let systemPrompt = """
        You are an expert DJ AI.
        Create a playlist from the provided library.
        Event/Mood requested: \(prompt)
        Target Track Count: \(count)

        Library format: PersistentID|Artist|Title|Genre|Year
        \(libraryText)

        CRITICAL RULES:
        1. Select exactly \(count) tracks. If you cannot find perfect matches, select the closest alternatives based on artist style or genre to ensure you reach the target count.
        2. You MUST return ONLY the 16-character hexadecimal PersistentID for each selected track.
        3. DO NOT return track titles or artist names. Only the IDs (the first part of each line).
        4. Your ENTIRE output MUST BE ONLY a single, flat JSON array of these ID strings.
        5. DO NOT add explanations, notes, or markdown.
        CORRECT OUTPUT FORMAT: ["A1B2C3D4E5F67890", "0987654321ABCDEF"]
        """

        if provider == "Groq" {
            url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
            request = URLRequest(url: url)
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": "You are a strict data API. You MUST output ONLY a valid JSON array of strings."],
                    ["role": "user", "content": systemPrompt]
                ],
                "temperature": 0.3
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else if provider == "OpenRouter" {
            url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            request = URLRequest(url: url)
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("https://github.com/MiChiRose/Syncrosa", forHTTPHeaderField: "HTTP-Referer")
            request.addValue("Syncrosa-M", forHTTPHeaderField: "X-Title")
            let body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": "You are a strict data API. You MUST output ONLY a valid JSON array of strings."],
                    ["role": "user", "content": systemPrompt]
                ],
                "temperature": 0.3
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            // Gemini
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "contents": [["parts": [["text": systemPrompt]]]]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                var text = ""
                
                if provider == "Gemini" {
                    if let candidates = json?["candidates"] as? [[String: Any]],
                       let firstCandidate = candidates.first,
                       let content = firstCandidate["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]] {
                        text = parts.first?["text"] as? String ?? ""
                    }
                } else {
                    if let choices = json?["choices"] as? [[String: Any]],
                       let message = choices.first?["message"] as? [String: Any] {
                        text = message["content"] as? String ?? ""
                    }
                }
                
                // Regex to find 16-char hex IDs
                let regex = try NSRegularExpression(pattern: "([a-fA-F0-9]{16})", options: [])
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                let ids = matches.compactMap { match -> String? in
                    if let range = Range(match.range(at: 1), in: text) {
                        return String(text[range])
                    }
                    return nil
                }
                
                var uniqueIds: [String] = []
                for id in ids {
                    if !uniqueIds.contains(id) {
                        uniqueIds.append(id)
                    }
                }
                completion(Array(uniqueIds.prefix(count)))
            } catch {
                completion(nil)
            }
        }.resume()
    }
}
