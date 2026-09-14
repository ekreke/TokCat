import Foundation
import TokCatCore

/// 模型定价加载：优先使用 cc-switch 同步的 models.dev 定价快照。
public enum ModelPricingStore {
    /// 读取 `~/.cc-switch/model-pricing.json`（models.dev 同步产物）。
    public static func loadCCSwitchJSON(path: String = AgentPaths.ccSwitchPricing) -> ModelPricingTable {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else {
            return .empty
        }
        let parsed: [ModelPricing] = models.compactMap { entry in
            guard let modelId = entry["modelId"] as? String else { return nil }
            return ModelPricing(
                modelId: modelId,
                inputCostPerMillion: number(entry["inputCostPerMillion"]),
                outputCostPerMillion: number(entry["outputCostPerMillion"]),
                cacheReadCostPerMillion: number(entry["cacheReadCostPerMillion"]),
                cacheWriteCostPerMillion: number(entry["cacheCreationCostPerMillion"])
            )
        }
        return ModelPricingTable(models: parsed)
    }

    /// 读取 cc-switch 数据库中的 `model_pricing` 表（JSON 文件不存在时的兜底）。
    public static func loadCCSwitchDB(path: String = AgentPaths.ccSwitchDB) -> ModelPricingTable {
        guard let db = SQLiteRO(path: path) else { return .empty }
        var models: [ModelPricing] = []
        db.query(
            """
            SELECT model_id, input_cost_per_million, output_cost_per_million,
                   cache_read_cost_per_million, cache_creation_cost_per_million
            FROM model_pricing
            """
        ) { row in
            guard let modelId = row.string(0) else { return }
            models.append(ModelPricing(
                modelId: modelId,
                inputCostPerMillion: row.double(1),
                outputCostPerMillion: row.double(2),
                cacheReadCostPerMillion: row.double(3),
                cacheWriteCostPerMillion: row.double(4)
            ))
        }
        return ModelPricingTable(models: models)
    }

    /// 依次尝试本地可用来源。
    public static func loadDefault() -> ModelPricingTable {
        let json = loadCCSwitchJSON()
        if !json.isEmpty { return json }
        return loadCCSwitchDB()
    }

    private static func number(_ value: Any?) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }
}
