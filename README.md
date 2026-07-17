<h1 align="center">Console - CensorChecker</h1>
<h3 align="center">- Check Check Need Network Censorship -</h3>
</br>

## 自我介绍

**Console CensorChecker**: 一只基于 **Pwsh(.Net 8)** 的 Tcping 批量拨测与审查检测脚本

- 适用平台: Any

## 注意事项

本项目仅供测试 Tcping 延迟与监控服务可用性，无意绕过任何审查设备的审查

## 下载地址

1. Github Release: [https://github.com/SpaceTimee/Console-CensorChecker/releases](https://github.com/SpaceTimee/Console-CensorChecker/releases)
2. PowerShell Gallery: [https://www.powershellgallery.com/packages/Console-CensorChecker](https://www.powershellgallery.com/packages/Console-CensorChecker)
3. Github Marketplace: [https://github.com/marketplace/actions/console-censorchecker](https://github.com/marketplace/actions/console-censorchecker)

## 安装方式

PowerShell Module: `Install-Module Console-CensorChecker`

## 食用方式

1. PowerShell Script: 在 pwsh 7.x 环境中运行 Console-CensorChecker.ps1 脚本 → 按照提示操作即可
2. PowerShell Module: 在 pwsh 7.x 环境中执行 Invoke-Check 命令即可

```powershell
Invoke-Check -targets example.com
```

3. MCP Server: 在 pwsh 7.x 环境中执行 Invoke-Check -mcp 即可

```powershell
Invoke-Check -mcp
```

4. MCP Client: 在 Agent 客户端中添加 MCP 配置即可

```json
{
    "mcpServers": {
        "console-censorchecker": {
            "command": "pwsh",
            "args": ["-Command", "Invoke-Check -mcp"]
        }
    }
}
```

5. Github Actions: 在工作流中调用 SpaceTimee/Console-CensorChecker 即可

```yaml
- uses: SpaceTimee/Console-CensorChecker@v1.1.4.53
  with:
      TARGETS: example.com
```

## MCP 托管

1. Smithery (首选): [https://smithery.ai/servers/spacetime/console-censorchecker](https://smithery.ai/servers/spacetime/console-censorchecker)
2. Glama: [https://glama.ai/mcp/servers/SpaceTimee/Console-CensorChecker](https://glama.ai/mcp/servers/SpaceTimee/Console-CensorChecker)

## 开发者

**Space Time**

## 联系方式

1. **QQ 群 (主群): 964102080，1034315671，716266896，338919498**
2. TG 群 (分群): [PixCealerChat](https://t.me/PixCealerChat)
3. **邮箱: Zeus6_6@163.com**

•ᴗ•
