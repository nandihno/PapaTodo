import Testing
@testable import PapaTodos

struct PapaTodosTests {
    @Test func appConfigurationLoadsFromInfoPlist() throws {
        let configuration = try AppConfiguration.load()

        #expect(configuration.supabaseURL.host == "apaeocgssnkncputzolu.supabase.co")
        #expect(!configuration.supabaseAnonKey.isEmpty)
        #expect(configuration.bundleIdentifier == "org.nando.PapaTodos")
        #expect(configuration.apnsEnvironment == .sandbox)
    }
}
