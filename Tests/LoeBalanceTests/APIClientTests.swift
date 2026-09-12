import Foundation
import XCTest
@testable import LoeBalance

final class APIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testLoginSendsOnlyEmailAndPasswordAndDecodesSession() async throws {
        let capturedRequest = LockedBox<URLRequest?>(nil)
        let capturedBody = LockedBox<Data?>(nil)
        URLProtocolStub.install { request in
            capturedRequest.set(request)
            capturedBody.set(try request.bodyData())
            return Self.response(
                for: request,
                json: #"{"code":0,"message":"ok","data":{"access_token":"access-token","refresh_token":"refresh-token","expires_in":3600,"token_type":"Bearer","user":{"id":42,"balance":"19.38","ignored":true}}}"#
            )
        }

        let session = try await makeClient().login(email: "user@example.com", password: "secret123")

        XCTAssertEqual(session, .fixture)
        let request = try XCTUnwrap(capturedRequest.value)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.loe.cx/api/v1/auth/login")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(capturedBody.value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["email": "user@example.com", "password": "secret123"])
    }

    func testRefreshUsesReturnedUserID() async throws {
        let capturedRequest = LockedBox<URLRequest?>(nil)
        let capturedBody = LockedBox<Data?>(nil)
        URLProtocolStub.install { request in
            capturedRequest.set(request)
            capturedBody.set(try request.bodyData())
            return Self.response(
                for: request,
                json: #"{"code":0,"data":{"access_token":"opaque-access-token","refresh_token":"rotated-token","expires_in":900,"token_type":"Bearer","user":{"id":84}},"message":"ok"}"#
            )
        }

        let session = try await makeClient().refresh(refreshToken: "refresh-token")

        XCTAssertEqual(session.refreshToken, "rotated-token")
        XCTAssertEqual(session.expiresAt, .fixtureNow.addingTimeInterval(900))
        XCTAssertEqual(session.userID, 84)
        let request = try XCTUnwrap(capturedRequest.value)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.loe.cx/api/v1/auth/refresh")
        let body = try XCTUnwrap(capturedBody.value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["refresh_token": "refresh-token"])
    }

    func testRefreshWithoutUserAcceptsOpaqueTokenAndReturnsNilUserID() async throws {
        URLProtocolStub.install { request in
            Self.response(
                for: request,
                json: #"{"code":0,"data":{"access_token":"opaque-access-token","refresh_token":"rotated-token","expires_in":900},"message":"ok"}"#
            )
        }

        let session = try await makeClient().refresh(refreshToken: "refresh-token")

        XCTAssertEqual(session.accessToken, "opaque-access-token")
        XCTAssertEqual(session.refreshToken, "rotated-token")
        XCTAssertEqual(session.expiresAt, .fixtureNow.addingTimeInterval(900))
        XCTAssertNil(session.userID)
    }

    func testAuthenticatedGETRequestsIncludeRequiredHeaders() async throws {
        let capturedRequests = LockedBox<[URLRequest]>([])
        URLProtocolStub.install { request in
            capturedRequests.update { $0.append(request) }
            switch request.url?.path {
            case "/api/v1/auth/me":
                return Self.response(for: request, json: #"{"code":0,"data":{"balance":"19.38","extra":"ignored"},"message":"ok"}"#)
            case "/api/v1/usage/dashboard/stats":
                return Self.response(for: request, json: #"{"code":0,"data":{"today_requests":7,"today_actual_cost":"0.30","total_requests":99},"message":"ok"}"#)
            default:
                return Self.response(for: request, json: #"{"code":0,"data":{"items":[],"total":0,"page":1,"page_size":100,"pages":0},"message":"ok"}"#)
            }
        }

        let client = makeClient()
        _ = try await client.fetchCurrentUser(accessToken: "access-token")
        _ = try await client.fetchDashboardStats(accessToken: "access-token")
        _ = try await client.fetchUsage(accessToken: "access-token", pageSize: 100)

        XCTAssertEqual(capturedRequests.value.count, 3)
        for request in capturedRequests.value {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "zh")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-User-UI-Request"), "1")
        }
    }

    func testDTOsRequireUsedFieldsAndIgnoreUnrelatedFields() async throws {
        URLProtocolStub.install { request in
            switch request.url?.path {
            case "/api/v1/auth/me":
                return Self.response(for: request, json: #"{"code":0,"data":{"id":42,"email":"user@example.com","username":"user","balance":"19.38","role":"user"},"message":"ok","trace_id":"ignored"}"#)
            default:
                return Self.response(for: request, json: #"{"code":0,"data":{"today_requests":7,"today_actual_cost":"0.30","rpm":12.5},"message":"ok"}"#)
            }
        }

        let client = makeClient()
        let user = try await client.fetchCurrentUser(accessToken: "access-token")
        let stats = try await client.fetchDashboardStats(accessToken: "access-token")

        XCTAssertEqual(user.balance, money("19.38"))
        XCTAssertEqual(user.id, 42)
        XCTAssertEqual(user.email, "user@example.com")
        XCTAssertEqual(user.username, "user")
        XCTAssertEqual(stats.todayRequests, 7)
        XCTAssertEqual(stats.todayActualCost, money("0.30"))
    }

    func testFetchUsageSendsPaginationAndDecodesFlexibleDates() async throws {
        let capturedRequest = LockedBox<URLRequest?>(nil)
        URLProtocolStub.install { request in
            capturedRequest.set(request)
            return Self.response(
                for: request,
                json: #"{"code":0,"data":{"items":[{"id":11,"created_at":"2026-09-12T08:15:30Z","actual_cost":"0.10","model":"ignored"},{"id":12,"created_at":"2026-09-12T08:15:30.125Z","actual_cost":0.20}],"total":2,"page":1,"page_size":100,"pages":1,"extra":true},"message":"ok"}"#
            )
        }

        let records = try await makeClient().fetchUsage(accessToken: "access-token", pageSize: 100)

        XCTAssertEqual(records.map(\.id), [11, 12])
        XCTAssertEqual(records.map(\.actualCost), [money("0.10"), money("0.20")])
        XCTAssertEqual(records[1].createdAt.timeIntervalSince(records[0].createdAt), 0.125, accuracy: 0.000_001)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(capturedRequest.value?.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/v1/usage")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "page_size", value: "100")])
    }

    func testNonzeroEnvelopeMapsToAPIEnvelopeError() async {
        URLProtocolStub.install { request in
            Self.response(for: request, json: #"{"code":4007,"data":null,"message":"account disabled"}"#)
        }

        await assertError(.apiEnvelope(code: 4007, message: "account disabled")) {
            try await self.makeClient().fetchCurrentUser(accessToken: "access-token")
        }
    }

    func testNonzeroEnvelopeIgnoresIncompatibleNonNullErrorData() async {
        URLProtocolStub.install { request in
            Self.response(
                for: request,
                json: #"{"code":4008,"data":{"unexpected":true},"message":"quota unavailable"}"#
            )
        }

        await assertError(.apiEnvelope(code: 4008, message: "quota unavailable")) {
            try await self.makeClient().fetchCurrentUser(accessToken: "access-token")
        }
    }

    func testHTTP401MapsToUnauthorized() async {
        URLProtocolStub.install { request in
            Self.response(for: request, status: 401, json: #"{"code":401,"message":"expired","data":null}"#)
        }

        await assertError(.unauthorized) {
            try await self.makeClient().fetchCurrentUser(accessToken: "access-token")
        }
    }

    func testHTTP429MapsToRateLimitedWithRetryAfter() async {
        URLProtocolStub.install { request in
            Self.response(
                for: request,
                status: 429,
                headers: ["Retry-After": "120"],
                json: #"{"code":429,"message":"slow down","data":null}"#
            )
        }

        await assertError(.rateLimited(retryAfter: .fixtureNow.addingTimeInterval(120))) {
            try await self.makeClient().fetchCurrentUser(accessToken: "access-token")
        }
    }

    func testMalformedJSONMapsToInvalidResponse() async {
        URLProtocolStub.install { request in
            Self.response(for: request, json: #"{"code":0,"data":not-json}"#)
        }

        await assertError(.invalidResponse) {
            try await self.makeClient().fetchCurrentUser(accessToken: "access-token")
        }
    }

    func testURLErrorMapsToTransportError() async {
        URLProtocolStub.install { _ in
            throw URLError(.notConnectedToInternet)
        }

        await assertError(.transport(URLError(.notConnectedToInternet))) {
            try await self.makeClient().fetchCurrentUser(accessToken: "access-token")
        }
    }

    func testMissingRequiredDTOFieldMapsToInvalidResponse() async {
        URLProtocolStub.install { request in
            Self.response(for: request, json: #"{"code":0,"data":{"id":42},"message":"ok"}"#)
        }

        await assertError(.invalidResponse) {
            try await self.makeClient().fetchCurrentUser(accessToken: "access-token")
        }
    }

    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return APIClient(session: URLSession(configuration: configuration), now: { .fixtureNow })
    }

    private func money(_ value: String) -> Money {
        Money(decimal: Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!)
    }

    private func assertError<T>(
        _ expected: AppError,
        operation: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AppError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AppError, got \(error)", file: file, line: line)
        }
    }

    private static func response(
        for request: URLRequest,
        status: Int = 200,
        headers: [String: String] = [:],
        json: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (response, Data(json.utf8))
    }
}
