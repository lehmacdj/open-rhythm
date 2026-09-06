import Foundation

enum SonolusClientError: LocalizedError {
  case invalidURL
  case invalidResponse
  case httpStatus(Int)

  var errorDescription: String? {
    switch self {
    case .invalidURL: "The server URL is invalid."
    case .invalidResponse: "The server returned an invalid response."
    case .httpStatus(let status): "The server returned HTTP \(status)."
    }
  }
}

actor SonolusClient {
  private let session: URLSession
  private let decoder = JSONDecoder()

  init(session: URLSession = .shared) {
    self.session = session
  }

  func levels(
    on server: ServerDescriptor,
    page: Int,
    query: String = "",
    locale: Locale = .current
  ) async throws -> SonolusLevelList {
    let language = locale.language.languageCode?.identifier ?? "en"
    var components = URLComponents(
      url: server.baseURL.appendingPathComponent("sonolus/levels/list"),
      resolvingAgainstBaseURL: false
    )
    var queryItems = [
      URLQueryItem(name: "localization", value: language),
      URLQueryItem(name: "page", value: String(page))
    ]
    if !query.isEmpty {
      queryItems.append(URLQueryItem(name: "type", value: "advanced"))
      queryItems.append(URLQueryItem(name: "keywords", value: query))
    }
    components?.queryItems = queryItems

    guard let url = components?.url else {
      throw SonolusClientError.invalidURL
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw SonolusClientError.invalidResponse
    }
    guard 200..<300 ~= response.statusCode else {
      throw SonolusClientError.httpStatus(response.statusCode)
    }
    return try decoder.decode(SonolusLevelList.self, from: data)
  }
}

