/*
 * Copyright 2024-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import type { MarkdownIt } from 'markdown-it';

export default (md: MarkdownIt) => {
  const temp = md.renderer.rules.fence.bind(md.renderer.rules);
  md.renderer.rules.fence = (tokens, idx, options, env, slf) => {
    const token = tokens[idx];
    if (token.info === 'echarts') {
      const code = token.content.trim();
      // 检查是否有完整的JSON结构，这里简单检查是否包含至少一个完整的键值对和正确的闭合括号
      const hasValidJson =
        /\{[\s\S]*\}/.test(code) && code.match(/\{/g)?.length === code.match(/\}/g)?.length;
      if (hasValidJson) {
        try {
          const json = JSON.parse(code);
          const width = '100%';
          const height = 400;
          return `<div style="width:${width};height:${height}px" class="md-echarts">${JSON.stringify(json)}</div>`;
        } catch {
          // JSON.parse 失败：可能是 LLM/Python 生成了包含 function 的 JS 对象字面量（如 formatter: function(param){...}）
          // JSON 不支持函数，尝试用 new Function 解析，与 ReportTemplateUtil / report-html-template 保持一致
          try {
            new Function('return (' + code + ')')(); // 校验可解析，实际渲染由 MarkdownAgentContainer 负责
            const width = '100%';
            const height = 400;
            return `<div style="width:${width};height:${height}px" class="md-echarts" data-echarts-raw="${encodeURIComponent(code)}"></div>`;
          } catch (e) {
            return `<pre>echarts配置格式错误: ${(e as Error).message}</pre>`;
          }
        }
      } else {
        // 如果JSON结构不完整，返回原始代码块，不进行渲染
        return `<pre><code class="language-echarts md-echarts">${code}</code></pre>`;
      }
    }
    return temp(tokens, idx, options, env, slf);
  };
};
