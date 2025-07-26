#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ErrorCode,
  ListToolsRequestSchema,
  McpError,
} from "@modelcontextprotocol/sdk/types.js";
import axios from "axios";

interface TutorialStep {
  id: string;
  text: string;
  x: number;
  y: number;
  width: number;
  height: number;
  description: string;
}

interface AnalysisResult {
  message: string;
  tutorial_steps: TutorialStep[];
}

class ScreenshotAnalysisServer {
  private server: Server;
  private claudeApiKey: string;
  private claudeApiUrl: string = "https://api.anthropic.com/v1/messages";

  constructor() {
    this.server = new Server(
      {
        name: "screenshot-analysis-server",
        version: "1.0.0",
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.claudeApiKey = process.env.CLAUDE_API_KEY || "";

    if (!this.claudeApiKey) {
      console.error("⚠️ CLAUDE_API_KEY環境変数が設定されていません");
    }

    this.setupToolHandlers();
  }

  private setupToolHandlers() {
    this.server.setRequestHandler(ListToolsRequestSchema, async () => {
      return {
        tools: [
          {
            name: "analyze_screenshot",
            description:
              "スクリーンショットをClaude AIで分析し、UI要素の位置とチュートリアルステップを生成します",
            inputSchema: {
              type: "object",
              properties: {
                image_data: {
                  type: "string",
                  description: "base64エンコードされた画像データ",
                },
                question: {
                  type: "string",
                  description: "ユーザーからの質問",
                },
                screen_width: {
                  type: "number",
                  description: "論理スクリーン幅",
                },
                screen_height: {
                  type: "number",
                  description: "論理スクリーン高さ",
                },
                scale_factor: {
                  type: "number",
                  default: 2.0,
                  description: "Retinaディスプレイのスケールファクター",
                },
              },
              required: [
                "image_data",
                "question",
                "screen_width",
                "screen_height",
              ],
              additionalProperties: false,
            },
          },
          {
            name: "verify_overlay_accuracy",
            description:
              "オーバーレイ表示後のスクリーンショットを撮影し、赤枠の位置精度を検証します（AIによる自己校正）",
            inputSchema: {
              type: "object",
              properties: {
                image_data: {
                  type: "string",
                  description:
                    "オーバーレイ表示後のbase64エンコードされた画像データ",
                },
                original_prediction: {
                  type: "object",
                  description: "元の予測結果",
                  properties: {
                    text: { type: "string" },
                    x: { type: "number" },
                    y: { type: "number" },
                    width: { type: "number" },
                    height: { type: "number" },
                    description: { type: "string" },
                  },
                  required: [
                    "text",
                    "x",
                    "y",
                    "width",
                    "height",
                    "description",
                  ],
                },
                screen_width: {
                  type: "number",
                  description: "論理スクリーン幅",
                },
                screen_height: {
                  type: "number",
                  description: "論理スクリーン高さ",
                },
                scale_factor: {
                  type: "number",
                  default: 2.0,
                  description: "Retinaディスプレイのスケールファクター",
                },
              },
              required: [
                "image_data",
                "original_prediction",
                "screen_width",
                "screen_height",
              ],
              additionalProperties: false,
            },
          },
          {
            name: "create_test_tutorial",
            description: "テスト用の固定座標チュートリアルステップを生成します",
            inputSchema: {
              type: "object",
              properties: {
                count: {
                  type: "number",
                  default: 3,
                  description: "生成するテストステップ数",
                },
              },
              additionalProperties: false,
            },
          },
        ],
      };
    });

    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args } = request.params;

      try {
        switch (name) {
          case "analyze_screenshot":
            return await this.analyzeScreenshot(args);

          case "verify_overlay_accuracy":
            return await this.verifyOverlayAccuracy(args);

          case "create_test_tutorial":
            return await this.createTestTutorial(args);

          default:
            throw new McpError(
              ErrorCode.MethodNotFound,
              `Unknown tool: ${name}`
            );
        }
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : String(error);
        throw new McpError(
          ErrorCode.InternalError,
          `Tool execution failed: ${errorMessage}`
        );
      }
    });
  }

  private async analyzeScreenshot(args: any) {
    const {
      image_data,
      question,
      screen_width,
      screen_height,
      scale_factor = 2.0,
    } = args;

    console.error("🤖 Claude API分析開始...");

    const systemPrompt = `あなたはmacOSのUI構造を深く理解するエキスパートアシスタントです。

スクリーン情報:
- 論理解像度: ${screen_width}x${screen_height}
- スケールファクタ: ${scale_factor}
- このスクリーンショットは物理ピクセルで撮影されています

## macOSのUI構造を正確に理解してください：

### 1. メニューバー（画面最上部、通常y=0-30付近）
- アプリ名、ファイル、編集、表示などのメニュー項目
- 右側にWi-Fi、バッテリー、時計などのシステムメニュー

### 2. アプリケーションウィンドウ（画面中央部）
- 実際に起動中のアプリケーション（Finder、Safari、VSCodeなど）
- 各ウィンドウには左上に赤・黄・緑の丸ボタン（ウィンドウコントロール）

### 3. Dock（画面下部）
- アプリケーションアイコンが並んでいる領域

## 質問の意図を正確に理解してください：

**「アプリが起動している」「どのようなアプリ」**
→ メニューバーではなく、実際のアプリケーションウィンドウを検出
→ ウィンドウのタイトルバーやアプリの特徴的な部分を特定

**「閉じるボタン」「終了ボタン」**
→ 各ウィンドウの左上の赤い小さな丸ボタンを検出
→ サイズは通常12x12ピクセル程度

**「メニュー」**
→ 画面最上部のメニューバー項目を検出

## 重要な検出ルール：
1. 質問の意図に最も適合するUI要素のみを検出
2. メニューバー項目の過度な検出を避ける
3. アプリウィンドウとメニューバーを明確に区別する
4. 座標は物理ピクセル座標で指定（スクリーンショットの実際のピクセル座標）

以下のJSON形式で回答してください：
{
  "message": "ユーザーへの説明メッセージ",
  "tutorial_steps": [
    {
      "text": "UI要素の名前",
      "x": 100,
      "y": 100,
      "width": 200,
      "height": 50,
      "description": "詳細説明"
    }
  ]
}

座標は画面左上を(0,0)とした絶対座標で指定してください。
UI要素が見つからない場合は、tutorial_stepsを空の配列にしてください。`;

    // リトライ機能付きでClaude API呼び出し
    let response: any = null;
    let lastError: any = null;
    const maxRetries = 3;
    const retryDelays = [2000, 5000, 10000]; // 2秒、5秒、10秒待機

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        console.error(`🔄 Claude API呼び出し試行 ${attempt + 1}/${maxRetries}`);

        response = await axios.post(
          this.claudeApiUrl,
          {
            model: "claude-3-5-sonnet-20241022",
            max_tokens: 1500,
            messages: [
              {
                role: "user",
                content: [
                  {
                    type: "image",
                    source: {
                      type: "base64",
                      media_type: "image/jpeg",
                      data: image_data,
                    },
                  },
                  {
                    type: "text",
                    text: question,
                  },
                ],
              },
            ],
            system: systemPrompt,
          },
          {
            headers: {
              "Content-Type": "application/json",
              "anthropic-version": "2023-06-01",
              "x-api-key": this.claudeApiKey,
            },
            timeout: 30000, // 30秒タイムアウト
          }
        );

        // 成功した場合はループを抜ける
        console.error("✅ Claude API呼び出し成功");
        break;
      } catch (error: any) {
        lastError = error;
        const status = error.response?.status;
        const shouldRetry =
          status === 529 || status === 503 || status === 502 || !status;

        console.error(
          `❌ Claude API呼び出し失敗 (試行 ${attempt + 1}): ${
            status || "Network Error"
          }`
        );

        if (!shouldRetry || attempt === maxRetries - 1) {
          console.error(
            "🚫 リトライ不可能なエラーまたは最大試行回数に達しました"
          );
          break;
        }

        // 指数バックオフで待機
        const delay = retryDelays[attempt] || 10000;
        console.error(`⏰ ${delay / 1000}秒後にリトライします...`);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }

    // エラーが発生した場合の処理
    if (lastError && !response) {
      console.error("💥 Claude API呼び出し最終的に失敗:", lastError.message);

      // 529エラーの場合は特別なメッセージを返す
      if (lastError.response?.status === 529) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: false,
                error:
                  "Claude APIサーバーが一時的に過負荷状態です。しばらく待ってから再試行してください。",
                error_code: 529,
                retry_suggested: true,
                message:
                  "API過負荷のため画面分析を実行できませんでした。数分後に再度お試しください。",
                tutorial_steps: [],
              }),
            },
          ],
        };
      }

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              success: false,
              error: `Claude API分析に失敗しました: ${lastError.message}`,
              tutorial_steps: [],
            }),
          },
        ],
      };
    }

    // 成功した場合の処理
    try {
      const responseText = response.data.content[0]?.text || "";
      console.error("✅ Claude API応答受信");
      console.error(
        "🔍 Claude生応答（最初の500文字）:",
        responseText.slice(0, 500)
      );

      // JSON部分を抽出
      const jsonMatch = responseText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        const analysisResult: AnalysisResult = JSON.parse(jsonMatch[0]);
        console.error(
          "📋 抽出されたJSON:",
          JSON.stringify(analysisResult, null, 2)
        );

        // 座標変換（物理→論理）
        const convertedSteps = analysisResult.tutorial_steps.map(
          (step, index) => ({
            id: `step_${index + 1}`,
            text: step.text,
            x: step.x / scale_factor,
            y: step.y / scale_factor,
            width: step.width / scale_factor,
            height: step.height / scale_factor,
            description: step.description,
          })
        );

        console.error(
          `🎯 解析結果: ${convertedSteps.length}個のチュートリアルステップ`
        );

        // 各UI要素の詳細をログ出力
        convertedSteps.forEach((step, index) => {
          console.error(`📍 ステップ${index + 1}: ${step.text}`);
          console.error(
            `   座標: (${step.x.toFixed(1)}, ${step.y.toFixed(1)})`
          );
          console.error(
            `   サイズ: ${step.width.toFixed(1)} x ${step.height.toFixed(1)}`
          );
          console.error(`   説明: ${step.description}`);
        });

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                message: analysisResult.message,
                tutorial_steps: convertedSteps,
              }),
            },
          ],
        };
      } else {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                message: responseText,
                tutorial_steps: [],
              }),
            },
          ],
        };
      }
    } catch (error) {
      console.error("❌ レスポンス処理エラー:", error);
      const errorMessage =
        error instanceof Error ? error.message : String(error);

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              success: false,
              error: `レスポンス処理に失敗しました: ${errorMessage}`,
              tutorial_steps: [],
            }),
          },
        ],
      };
    }
  }

  private async verifyOverlayAccuracy(args: any) {
    const {
      image_data,
      original_prediction,
      screen_width,
      screen_height,
      scale_factor = 2.0,
    } = args;

    console.error("🔍 AIによる自己校正開始...");
    console.error("📊 原予測:", JSON.stringify(original_prediction, null, 2));

    const systemPrompt = `あなたはAIの自己校正を行うエキスパートです。

## 検証タスク：
前回のAI分析で「${original_prediction.text}」の位置を以下のように予測しました：
- 予測座標: (${original_prediction.x}, ${original_prediction.y})
- 予測サイズ: ${original_prediction.width} x ${original_prediction.height}

このスクリーンショットには、予測した位置に赤い枠が表示されています。
この赤枠が実際のUI要素「${
      original_prediction.text
    }」を正確に囲んでいるかを検証してください。

## 評価基準：
1. **位置精度**: 赤枠がUI要素の中心部を正確に捉えているか
2. **サイズ精度**: 赤枠のサイズがUI要素に適切か
3. **全体的な精度**: ユーザーが理解しやすい位置にあるか

## 回答形式：
{
  "accuracy_score": 0.85,
  "position_offset": {
    "x": -10,
    "y": 5
  },
  "size_correction": {
    "width": 20,
    "height": -5
  },
  "feedback": "赤枠は概ね正確ですが、少し左にずれています。",
  "corrected_position": {
    "x": ${original_prediction.x + 10},
    "y": ${original_prediction.y - 5},
    "width": ${original_prediction.width - 20},
    "height": ${original_prediction.height + 5}
  }
}

- accuracy_score: 0.0（完全に外れ）〜1.0（完璧）
- position_offset: 必要な位置補正（ピクセル、論理座標）
- size_correction: 必要なサイズ補正（ピクセル、論理座標）
- feedback: 人間向けのフィードバック
- corrected_position: 修正後の推奨座標（論理座標）`;

    try {
      const response = await axios.post(
        this.claudeApiUrl,
        {
          model: "claude-3-5-sonnet-20241022",
          max_tokens: 1000,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "image",
                  source: {
                    type: "base64",
                    media_type: "image/jpeg",
                    data: image_data,
                  },
                },
                {
                  type: "text",
                  text: "上記のスクリーンショットで赤枠の位置精度を評価してください。",
                },
              ],
            },
          ],
          system: systemPrompt,
        },
        {
          headers: {
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01",
            "x-api-key": this.claudeApiKey,
          },
        }
      );

      const responseText = response.data.content[0]?.text || "";
      console.error("✅ 自己校正分析完了");
      console.error(
        "🔍 検証応答（最初の300文字）:",
        responseText.slice(0, 300)
      );

      // JSON部分を抽出
      const jsonMatch = responseText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        try {
          // Claude APIの応答をクリーニング（+記号付き数値を正規化）
          let cleanedJson = jsonMatch[0];

          // +記号付き数値を正規化（例: "x": +15 → "x": 15）
          cleanedJson = cleanedJson.replace(/:\s*\+(-?\d+(?:\.\d+)?)/g, ": $1");

          // 他の潜在的な問題も修正
          cleanedJson = cleanedJson.replace(
            /:\s*\+(-?\d+(?:\.\d+)?)([,}])/g,
            ": $1$2"
          );

          // JSON文字列内の制御文字を適切にエスケープ
          cleanedJson = cleanedJson.replace(
            /("feedback":\s*"[^"]*?)[\n\r\t]/g,
            "$1\\n"
          );
          cleanedJson = cleanedJson.replace(
            /("feedback":\s*"[^"]*?)\n/g,
            "$1\\n"
          );
          cleanedJson = cleanedJson.replace(
            /("feedback":\s*"[^"]*?)\r/g,
            "$1\\r"
          );
          cleanedJson = cleanedJson.replace(
            /("feedback":\s*"[^"]*?)\t/g,
            "$1\\t"
          );

          // 文字列内の不正な改行文字を修正
          cleanedJson = cleanedJson.replace(
            /"feedback":\s*"([^"]*(?:\\.[^"]*)*)"/g,
            (match: string, content: string) => {
              const escapedContent = content
                .replace(/\n/g, "\\n")
                .replace(/\r/g, "\\r")
                .replace(/\t/g, "\\t")
                .replace(/[\x00-\x1F]/g, ""); // 他の制御文字を削除
              return `"feedback": "${escapedContent}"`;
            }
          );

          console.error("🧹 JSON クリーニング完了:");
          console.error("  原文:", jsonMatch[0].slice(0, 200));
          console.error("  修正:", cleanedJson.slice(0, 200));

          const verificationResult = JSON.parse(cleanedJson);
          console.error(
            "📋 検証結果:",
            JSON.stringify(verificationResult, null, 2)
          );

          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  success: true,
                  verification_result: verificationResult,
                  original_prediction: original_prediction,
                }),
              },
            ],
          };
        } catch (parseError) {
          console.error("❌ JSON パースエラー:", parseError);
          console.error("🔍 問題のあるJSON:", jsonMatch[0].slice(0, 500));

          // 手動解析のフォールバック処理
          const fallbackResult = this.parseVerificationFallback(jsonMatch[0]);
          if (fallbackResult) {
            console.error("✅ フォールバック解析成功");
            return {
              content: [
                {
                  type: "text",
                  text: JSON.stringify({
                    success: true,
                    verification_result: fallbackResult,
                    original_prediction: original_prediction,
                    note: "フォールバック解析を使用しました",
                  }),
                },
              ],
            };
          }

          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  success: false,
                  error: `JSON解析に失敗しました: ${
                    parseError instanceof Error
                      ? parseError.message
                      : String(parseError)
                  }`,
                  raw_response: responseText.slice(0, 500),
                }),
              },
            ],
          };
        }
      } else {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: false,
                error: "検証結果のJSON抽出に失敗しました",
                raw_response: responseText,
              }),
            },
          ],
        };
      }
    } catch (error) {
      console.error("❌ 自己校正エラー:", error);
      const errorMessage =
        error instanceof Error ? error.message : String(error);

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              success: false,
              error: `自己校正処理に失敗しました: ${errorMessage}`,
            }),
          },
        ],
      };
    }
  }

  private parseVerificationFallback(jsonText: string): any | null {
    try {
      console.error("🔧 フォールバック解析を開始...");

      // 基本的な数値抽出パターン
      const accuracyMatch = jsonText.match(
        /"accuracy_score":\s*([+-]?\d*\.?\d+)/
      );
      const xOffsetMatch = jsonText.match(/"x":\s*([+-]?\d+)/);
      const yOffsetMatch = jsonText.match(/"y":\s*([+-]?\d+)/);
      const widthMatch = jsonText.match(/"width":\s*([+-]?\d+)/);
      const heightMatch = jsonText.match(/"height":\s*([+-]?\d+)/);
      const feedbackMatch = jsonText.match(
        /"feedback":\s*"([^"]*(?:\\.[^"]*)*)"/
      );

      if (accuracyMatch) {
        const result = {
          accuracy_score: parseFloat(accuracyMatch[1]),
          position_offset: {
            x: xOffsetMatch ? parseInt(xOffsetMatch[1]) : 0,
            y: yOffsetMatch ? parseInt(yOffsetMatch[1]) : 0,
          },
          size_correction: {
            width: widthMatch ? parseInt(widthMatch[1]) : 0,
            height: heightMatch ? parseInt(heightMatch[1]) : 0,
          },
          feedback: feedbackMatch
            ? feedbackMatch[1].replace(/\\"/g, '"')
            : "フォールバック解析による結果",
          corrected_position: null, // 簡略化のためnull
        };

        console.error(
          "✅ フォールバック解析結果:",
          JSON.stringify(result, null, 2)
        );
        return result;
      }

      console.error("❌ フォールバック解析でも解析できませんでした");
      return null;
    } catch (error) {
      console.error("❌ フォールバック解析エラー:", error);
      return null;
    }
  }

  private async createTestTutorial(args: any) {
    const { count = 3 } = args;

    console.error(`🧪 テスト用チュートリアル作成 (${count}個のステップ)`);

    const testSteps: TutorialStep[] = [
      {
        id: "test_1",
        text: "テスト枠1",
        x: 100,
        y: 100,
        width: 200,
        height: 50,
        description: "左上テスト用座標",
      },
      {
        id: "test_2",
        text: "テスト枠2",
        x: 400,
        y: 300,
        width: 150,
        height: 80,
        description: "中央テスト用座標",
      },
      {
        id: "test_3",
        text: "テスト枠3",
        x: 800,
        y: 200,
        width: 120,
        height: 40,
        description: "右側テスト用座標",
      },
    ].slice(0, count);

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            success: true,
            message: `${count}個のテスト用チュートリアルステップを作成しました`,
            tutorial_steps: testSteps,
          }),
        },
      ],
    };
  }

  async run() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error("Screenshot Analysis MCP server running on stdio");
  }
}

const server = new ScreenshotAnalysisServer();
server.run().catch(console.error);
