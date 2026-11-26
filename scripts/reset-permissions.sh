#!/bin/bash
set -euo pipefail

echo "重置 SelectionTranslator 的辅助功能权限…"
tccutil reset Accessibility com.meteor.SelectionTranslator || true
echo "完成。重新打开 App 后，系统会再次询问权限。"
