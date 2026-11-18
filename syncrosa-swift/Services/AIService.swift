import Foundation
import CoreFoundation

class AIService {
    static let shared = AIService()
    
    static let defaultOpenRouterModel = "openrouter/free"
    private static let openRouterCacheKey = "openrouter_free_text_models"
    private var openRouterCallbacks: [([String]?) -> Void] = []
    private var lastOpenRouterRefresh: Date?

    var cachedOpenRouterModels: [String] {
        UserDefaults.standard.stringArray(forKey: Self.openRouterCacheKey) ?? [Self.defaultOpenRouterModel]
    }

    static func preferredOpenRouterModel(_ selected: String, in models: [String]) -> String {
        models.contains(selected) ? selected : defaultOpenRouterModel
    }

    static func freeOpenRouterModels(from data: Data) -> [String]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = object["data"] as? [Any],
              !entries.isEmpty else { return nil }
        let modelIDs = entries.compactMap { entry -> String? in
            guard let model = entry as? [String: Any],
                  let id = model["id"] as? String, id.hasSuffix(":free"),
                  let pricing = model["pricing"] as? [String: Any],
                  isZeroPrice(pricing["prompt"]), isZeroPrice(pricing["completion"]),
                  pricing["request"] == nil || isZeroPrice(pricing["request"]) else { return nil }
            if let architecture = model["architecture"] as? [String: Any] {
                if let input = architecture["input_modalities"] as? [String], !input.contains("text") { return nil }
                if let output = architecture["output_modalities"] as? [String], !output.contains("text") { return nil }
            }
            return id
        }
        // A valid catalog with no named free models still has the free router option.
        return [defaultOpenRouterModel] + Set(modelIDs).sorted()
    }

    private static func isZeroPrice(_ value: Any?) -> Bool {
        if let string = value as? String,
           let price = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
           let number = Double(string), number.isFinite {
            return price == .zero && number == 0
        }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue == 0
        }
        return false
    }

    // Serialize refreshes and deliver callbacks on the main queue for both screens.
    func fetchOpenRouterModels(force: Bool = false, completion: @escaping ([String]?) -> Void) {
        DispatchQueue.main.async {
            if !self.openRouterCallbacks.isEmpty {
                self.openRouterCallbacks.append(completion)
                return
            }
            if !force, let lastRefresh = self.lastOpenRouterRefresh,
               Date().timeIntervalSince(lastRefresh) < 5 * 60 {
                completion(self.cachedOpenRouterModels)
                return
            }

            self.openRouterCallbacks.append(completion)
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: request) { data, response, error in
                let models: [String]?
                if error == nil, let data, let response = response as? HTTPURLResponse,
                   (200...299).contains(response.statusCode) {
                    models = Self.freeOpenRouterModels(from: data)
                } else {
                    models = nil
                }
                DispatchQueue.main.async {
                    if let models {
                        UserDefaults.standard.set(models, forKey: Self.openRouterCacheKey)
                        self.lastOpenRouterRefresh = Date()
                    }
                    let callbacks = self.openRouterCallbacks
                    self.openRouterCallbacks.removeAll()
                    callbacks.forEach { $0(models) }
                }
            }.resume()
        }
    }

    func validateAPIKey(provider: String, apiKey: String, model: String, completion: @escaping (Bool, String) -> Void) {
        guard !apiKey.isEmpty else {
            completion(false, "API Key is empty")
            return
        }
        
        let url: URL
        var request: URLRequest
        
        if provider == "Groq" {
            guard let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
                completion(false, "Invalid service endpoint")
                return
            }
            url = endpoint
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
            guard let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
                completion(false, "Invalid service endpoint")
                return
            }
            url = endpoint
            request = URLRequest(url: url)
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": "Say 'OK'"]],
                "max_tokens": 128
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            // Gemini
            guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
                completion(false, "Invalid model name")
                return
            }
            url = endpoint
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            let body: [String: Any] = [
                "contents": [["parts": [["text": "Say 'OK'"]]]],
                "generationConfig": ["maxOutputTokens": 10]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            guard let data,
                  let response = response as? HTTPURLResponse else {
                completion(false, "No data received")
                return
            }
            guard (200...299).contains(response.statusCode) else {
                completion(false, "Service rejected the key (HTTP \(response.statusCode))")
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

        Library format: PersistentID<TAB>Artist<TAB>Title<TAB>Album<TAB>Genre<TAB>Year
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
            guard let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
                completion(nil)
                return
            }
            url = endpoint
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
            guard let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
                completion(nil)
                return
            }
            url = endpoint
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
            guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
                completion(nil)
                return
            }
            url = endpoint
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            let body: [String: Any] = [
                "contents": [["parts": [["text": systemPrompt]]]]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data,
                  error == nil,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
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
