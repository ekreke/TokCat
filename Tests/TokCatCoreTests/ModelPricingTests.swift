import XCTest
@testable import TokCatCore

final class ModelPricingTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(ModelPricingTable.normalize("Claude-Sonnet-5"), "claude-sonnet-5")
        XCTAssertEqual(ModelPricingTable.normalize("deepseek-v4-flash-free"), "deepseek-v4-flash")
        XCTAssertEqual(ModelPricingTable.normalize("openai/gpt-5.2"), "gpt-5.2")
        XCTAssertEqual(ModelPricingTable.normalize("glm-5.3-20260101"), "glm-5.3")
    }

    func testCostComputation() {
        let table = ModelPricingTable(models: [
            ModelPricing(modelId: "test-model", inputCostPerMillion: 10, outputCostPerMillion: 50,
                         cacheReadCostPerMillion: 1, cacheWriteCostPerMillion: 0)
        ])
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000)
        let cost = table.cost(of: "test-model", usage: usage)
        XCTAssertEqual(cost ?? -1, 10 + 50 + 1, accuracy: 0.0001)
    }

    func testUnknownModelReturnsNil() {
        let table = ModelPricingTable.empty
        XCTAssertNil(table.cost(of: "unknown", usage: TokenUsage(input: 1)))
    }

    func testConverterCostMode() {
        let table = ModelPricingTable(models: [
            ModelPricing(modelId: "m", inputCostPerMillion: 1_000_000, outputCostPerMillion: 0)
        ])
        let converter = TokenUnitConverter(metric: .cost, pricing: table)
        let sample = TokenSample(sourceId: "s", id: "1", at: Date(), model: "m",
                                 usage: TokenUsage(input: 2, output: 0))
        XCTAssertEqual(converter.units(for: sample), 2, accuracy: 0.0001)
        XCTAssertTrue(converter.unitIsCurrency)
    }

    func testConverterWeightedAndTotals() {
        let sample = TokenSample(sourceId: "s", id: "1", at: Date(), model: "m",
                                 usage: TokenUsage(input: 100, output: 100, cacheRead: 1000))
        XCTAssertEqual(TokenUnitConverter(metric: .total).units(for: sample), 1200, accuracy: 0.0001)
        XCTAssertEqual(TokenUnitConverter(metric: .inputOutput).units(for: sample), 200, accuracy: 0.0001)
        // 默认权重 cacheRead = 0.1
        XCTAssertEqual(TokenUnitConverter(metric: .weighted(.default)).units(for: sample), 300, accuracy: 0.0001)
    }
}
