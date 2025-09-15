# 本地AI模型文件

这个目录包含S2Y应用的本地AI模型文件。

## 文件结构

```
LocalModels/
├── README.md                    # 本文件
├── phi-3.5-mini-4bit.mlx       # Phi-3.5 Mini MLX模型文件 (主要模型)
├── tokenizer.json              # 分词器配置文件
├── config.json                 # 模型配置文件
└── model_info.json             # 模型元数据信息
```

## 模型信息

- **模型名称**: Phi-3.5 Mini Instruct
- **模型大小**: ~1.5GB (4-bit量化)
- **支持语言**: 中文、英文
- **专业领域**: 健康数据分析
- **硬件要求**: iOS 18+, 8GB+ RAM设备

## 部署说明

### 1. 模型准备

```bash
# 下载和转换Phi-3.5 Mini模型
python -m mlx_lm.convert \
  --hf-path microsoft/Phi-3.5-mini-instruct \
  --mlx-path ./phi-3.5-mini-4bit \
  --quantize --q-bits 4

# 复制文件到iOS项目
cp ./phi-3.5-mini-4bit/* ./S2Y/Resources/LocalModels/
```

### 2. 文件大小限制

- **App Store上传限制**: 2GB
- **建议策略**: 
  - 开发版：包含完整模型
  - 发布版：按需下载模型文件

### 3. 安全考虑

- 所有模型文件都经过完整性校验
- 模型文件不包含任何敏感信息
- 完全离线运行，不会上传用户数据

## 使用方法

模型文件会被`LocalHealthModelManager`自动加载：

```swift
let modelManager = LocalHealthModelManager.shared
await modelManager.loadModelIfNeeded()
```

## 文件校验

### SHA256校验和

更新模型文件后，请更新以下校验和：

```
phi-3.5-mini-4bit.mlx: [待更新]
tokenizer.json:        [待更新]
config.json:           [待更新]
```

## 故障排除

### 常见问题

1. **模型加载失败**
   - 检查文件完整性
   - 确认设备内存充足(>2GB可用)
   - 查看应用日志错误信息

2. **内存不足**
   - 关闭其他应用释放内存
   - 重启设备
   - 考虑使用更小的模型

3. **推理速度慢**
   - 确认设备支持Apple Silicon
   - 检查CPU使用率
   - 考虑模型量化级别

## 版本历史

- v1.0.0: 初始Phi-3.5 Mini集成
- v1.1.0: 添加健康领域优化
- v1.2.0: 性能和内存优化

## 许可证

本目录中的模型文件遵循以下许可证：

- Phi-3.5 Mini: MIT License (Microsoft)
- 自定义配置文件: MIT License (Stanford University)

---

**注意**: 实际部署时，模型文件可能通过按需下载方式获取，而不是打包在应用中。这样可以减小应用包大小，但需要首次使用时联网下载。