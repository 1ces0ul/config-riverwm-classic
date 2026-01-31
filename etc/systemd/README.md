---

# 🛡️ Mihomo-NFT-Fortress (Mihomo TUN 模式专属 nftables 安全方案)

这是一个专为 **Arch Linux** 笔记本用户设计的 `nftables` 极简防火墙配置。它在保证 **Mihomo (Clash.Meta) TUN 模式** 完美运行的前提下，通过“零信任”逻辑，为你的移动办公、咖啡馆公共 Wi-Fi 环境提供堡垒级的安全防护。

---

## 🌟 方案亮点

* **单文件搞定**：所有的防御逻辑、网卡信任、端口管理都在一个 `/etc/nftables.conf` 中，无需复杂脚本。
* **零信任 SSH**：无论内网公网，SSH 一律强制流量整形，彻底防御暴力破解。
* **跨环境免维护**：不依赖易变的 MAC 地址白名单，通过“私有网段过滤 + 应用层密码”实现无感切换。
* **隐身模式**：默认丢弃（Drop）所有非法包，不回复任何 Reject，使你的机器在公网扫描器面前完全“消失”。

---

## 🛠️ 第一步：配置 Mihomo (应用层防御)

在笔记本端开启防火墙前，必须确保应用层有“第二道锁”。修改你的 `config.yaml`：

```yaml
# 核心设置
allow-lan: true
bind-address: "*"  # 允许局域网设备连接
ipv6: false        # 根据需求开启，建议初学者关闭

# 设置内网通行证 (Layer 7 认证)
authentication:
  - "your_user:your_password" # 替换为你的用户名和密码

# 外部控制面板安全
secret: "your_strong_secret" # 替换面板密码

# TUN 模式确保网卡名为 Meta
tun:
  enable: true
  stack: system
  device: Meta
  auto-route: true
  auto-detect-interface: true

```

---

## 🛡️ 第二步：部署 nftables (网络层防御)

将以下科学配置写入 `/etc/nftables.conf`：

```nftables
#!/usr/bin/nft -f
# 清空规则
destroy table inet filter

table inet filter {
  # 定义 RFC1918 私有地址空间
  set private_networks {
    type ipv4_addr
    flags interval
    elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }
  }

  chain input {
    type filter hook input priority filter; policy drop;

    # 1. 基础信任链
    iif lo accept
    ct state {established, related} accept
    ct state invalid drop

    # 2. DHCP 支持 (确保公共 Wi-Fi 自动获取 IP)
    udp dport 68 accept

    # 3. Mihomo 深度适配
    iifname "Meta" accept        # 信任虚拟网卡
    ip daddr 198.19.0.0/16 accept # 放行 Fake-IP

    # 4. ICMP 策略 (仅允许 Ping 请求并限速)
    ip protocol icmp icmp type echo-request limit rate 5/second accept
    ip6 nexthdr icmpv6 icmpv6 type echo-request limit rate 5/second accept

    # 5. SSH 堡垒化 (全局强制频率限制)
    tcp dport ssh ct state new limit rate over 4/minute burst 2 packets drop
    tcp dport ssh accept

    # 6. 局域网服务分享 (纵深防御逻辑)
    # 仅允许私有网段连接代理端口，公网 IP 连探测的机会都没有
    ip saddr @private_networks tcp dport { 7890-7894, 9090 } ct state new accept
    ip saddr @private_networks udp dport { 7890-7894, 53, 5450 } ct state new accept
  }

  chain forward {
    type filter hook forward priority filter; policy drop;
    iifname "Meta" accept
    oifname "Meta" accept
  }

  chain output {
    type filter hook output priority filter; policy accept;
  }
}

```

---

## 🔍 原理解析：为什么这样最科学？

### 1. 状态追踪连接 (ct state new)

利用 `established, related` 机制，防火墙只对“新发起的对话（new）”进行耗费性能的地址比对，后续数据包直接秒过。

### 2. 纵深防御 (Defense in Depth)

即使攻击者伪造了内网 IP 地址，他也只能到达你的代理端口，而无法通过应用层（Mihomo）的用户名密码校验。

### 3. 隐身模式 (Stealth)

不使用 `reject` 回复，而是直接 `drop`。这使得扫描器（如 Nmap）会认为你的机器是离线状态，减少被针对性攻击的风险。

---

## 📝 运维手册

### 部署与自检

```bash
# 检查语法 (无输出即为正确)
sudo nft -c -f /etc/nftables.conf

# 重新加载规则
sudo nft -f /etc/nftables.conf

# 设置开机自启
sudo systemctl enable --now nftables

```

### 调试命令

```bash
# 查看拦截统计 (命中次数)
sudo nft list ruleset

# 实时查看连接追踪
sudo conntrack -L | grep 7890

```

---

## ⚠️ 风险提示

1. **SSH 封锁**：如果你自己在 1 分钟内连续失败连接 4 次，你也会被封锁 1 分钟。
2. **网卡名称**：本配置默认 Mihomo 网卡名为 `Meta`，如果你的配置不同，请手动修改。
3. **密钥登录**：强力建议配合 SSH Key 登录使用，关闭 `PasswordAuthentication`。

---

## 🤝 贡献与反馈

如果你在 PT 站下载、IPv6 适配或其他特殊场景下有更好的优化建议，欢迎提交 PR。

---
