'use strict';

const https = require('https');

const DEEPSEEK_HOST = 'api.deepseek.com';
const DEEPSEEK_PATH = '/chat/completions';
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY || 'sk-228e36edfcfc419695499d556487b3ad';
const MODEL = 'deepseek-chat';

function httpsPost(body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const options = {
      hostname: DEEPSEEK_HOST,
      port: 443,
      path: DEEPSEEK_PATH,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${DEEPSEEK_API_KEY}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
      timeout: 15000,
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try { resolve(JSON.parse(data)); }
          catch (e) { reject(new Error(`JSON parse error: ${data}`)); }
        } else {
          reject(new Error(`DeepSeek HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('DeepSeek request timeout')); });
    req.write(payload);
    req.end();
  });
}

/**
 * Tạo gợi ý câu hỏi cho người xem livestream.
 */
async function getAiSuggestions(productName, category, recentComments = []) {
  const chatContext = recentComments.length > 0
    ? `\nChat gần đây: ${recentComments.slice(0, 10).join(' | ')}`
    : '';

  const products = productName.split(',').map(s => s.trim()).filter(Boolean);
  const productList = products.length > 1
    ? products.map((p, i) => `${i + 1}. ${p}`).join('\n')
    : products[0];

  const prompt = `Livestream đang bán các sản phẩm:\n${productList}\n(danh mục: ${category})${chatContext}

Tạo đúng 3 câu hỏi ngắn gọn (dưới 12 từ mỗi câu) bằng tiếng Việt mà người xem có thể hỏi. Mỗi câu hỏi về một sản phẩm khác nhau nếu có nhiều sản phẩm. Câu hỏi thực tế, cụ thể.

Trả về JSON hợp lệ, không có text thêm:
{"suggestions": ["câu 1", "câu 2", "câu 3"]}`;

  const response = await httpsPost({
    model: MODEL,
    temperature: 0.7,
    max_tokens: 1000,
    messages: [
      {
        role: 'system',
        content: 'Bạn là trợ lý AI cho nền tảng livestream bán hàng Tropia. Tạo câu hỏi ngắn gọn, thực tế bằng tiếng Việt.',
      },
      { role: 'user', content: prompt },
    ],
  });

  const text = response.choices?.[0]?.message?.content || '';
  const jsonMatch = text.match(/\{[\s\S]*"suggestions"[\s\S]*\}/);
  if (!jsonMatch) throw new Error('Invalid DeepSeek response format');

  const parsed = JSON.parse(jsonMatch[0]);
  if (!Array.isArray(parsed.suggestions) || parsed.suggestions.length === 0) {
    throw new Error('No suggestions in response');
  }

  return parsed.suggestions.slice(0, 3);
}

/**
 * Tạo gợi ý câu trả lời cho host khi nhận câu hỏi từ viewer.
 */
async function getAutoReply(question, productName, category) {
  const products = productName.split(',').map(s => s.trim()).filter(Boolean);
  const productList = products.length > 1
    ? `các sản phẩm: ${products.join(', ')}`
    : `sản phẩm: ${products[0]}`;

  const prompt = `Người xem hỏi: "${question}"
Shop đang bán ${productList} (danh mục: ${category})

Trả lời ngắn gọn (dưới 20 từ) bằng tiếng Việt, đúng với các sản phẩm đang bán. Thân thiện, chuyên nghiệp. Chỉ trả về câu trả lời.`;

  const response = await httpsPost({
    model: MODEL,
    temperature: 0.7,
    max_tokens: 200,
    messages: [
      {
        role: 'system',
        content: 'Bạn là trợ lý AI giúp người bán hàng trả lời nhanh trong livestream. Trả lời ngắn gọn, thân thiện bằng tiếng Việt.',
      },
      { role: 'user', content: prompt },
    ],
  });

  return response.choices?.[0]?.message?.content?.trim() || '';
}

/**
 * Phân tích cảm xúc và hiệu quả buổi livestream, đề ra giải pháp cải thiện.
 * @param {{ viewer_count: number, like_count: number, cart_add_count: number, follow_count: number }} stats
 * @param {string} title - Tiêu đề buổi live
 * @returns {{ sentiment: string, summary: string, tips: string[] }}
 */
async function analyzeLiveSentiment(stats, title) {
  const { viewer_count = 0, like_count = 0, cart_add_count = 0, follow_count = 0 } = stats;

  const prompt = `Bạn là chuyên gia phân tích livestream bán hàng. Dưới đây là thống kê buổi live vừa kết thúc:

Tiêu đề buổi live: "${title}"
- Số người xem: ${viewer_count}
- Số lượt thích: ${like_count}
- Số lượt thêm giỏ hàng: ${cart_add_count}
- Số người theo dõi mới: ${follow_count}

Hãy phân tích hiệu quả buổi live và đưa ra đánh giá tổng quan. Dựa trên các chỉ số trên, hãy xác định:
1. Mức độ cảm xúc/hiệu quả: "tích cực" (tỉ lệ tương tác cao), "trung bình" (tương tác ở mức bình thường), hoặc "cần cải thiện" (tỉ lệ tương tác thấp).
2. Tóm tắt ngắn gọn (1-2 câu) bằng tiếng Việt về buổi live.
3. Đúng 4 giải pháp cụ thể, thực tế bằng tiếng Việt để cải thiện buổi live lần sau.

Trả về JSON hợp lệ, không có text thêm:
{"sentiment": "tích cực"|"trung bình"|"cần cải thiện", "summary": "...", "tips": ["tip1", "tip2", "tip3", "tip4"]}`;

  const response = await httpsPost({
    model: MODEL,
    temperature: 0.7,
    max_tokens: 1000,
    messages: [
      {
        role: 'system',
        content: 'Bạn là chuyên gia phân tích và tư vấn chiến lược cho người bán hàng livestream tại Việt Nam. Phân tích chính xác, đưa ra giải pháp thực tế.',
      },
      { role: 'user', content: prompt },
    ],
  });

  const text = response.choices?.[0]?.message?.content || '';
  const jsonMatch = text.match(/\{[\s\S]*"sentiment"[\s\S]*\}/);
  if (!jsonMatch) throw new Error('Invalid DeepSeek response format for sentiment analysis');

  const parsed = JSON.parse(jsonMatch[0]);
  if (!parsed.sentiment || !parsed.summary || !Array.isArray(parsed.tips) || parsed.tips.length < 4) {
    throw new Error('Incomplete sentiment analysis response');
  }

  return {
    sentiment: parsed.sentiment,
    summary:   parsed.summary,
    tips:      parsed.tips.slice(0, 4),
  };
}

module.exports = { getAiSuggestions, getAutoReply, analyzeLiveSentiment };
