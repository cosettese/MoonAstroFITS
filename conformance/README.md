# Astropy + FITSverify 对标验收

这组材料把 MoonAstroFITS 的结构解析结果与两个独立 FITS 工具链对照。夹具来自 NASA/GSFC 官方 64 位 FITS 样例页，具体来源和哈希见 [`fixtures/README.md`](fixtures/README.md)。

## 1. MoonAstroFITS 真实文件示例

推荐在有 native C 编译器的环境执行标准入口：

```text
moon run cmd/preflight --target native -- conformance/fixtures/test64bit1.fit
```

Windows 没有 C 编译器时，可用 Node.js/JS 入口完成相同的核心解析调用：

```text
moon run cmd/preflight-js --target js -- conformance/fixtures/test64bit1.fit
```

本次 JS 入口实测结果：

```text
bytes: 17280
structural validation: PASS (3 HDUs)
HDU 0: kind=PRIMARY data_bytes=120
  image: BITPIX=64 axes=[5, 3] pixels=15
HDU 1: kind=BINTABLE data_bytes=180
  table: rows=15 row_bytes=12 columns=2
    column 1: TFORM=1J width=4
    column 2: TFORM=1K width=8
    first row cells: 2
HDU 2: kind=BINTABLE data_bytes=1260
  table: unsupported or invalid fixed-width schema (... TFORM2 ... 1QK(15))
primary integer decode: PASS (15 samples, BSCALE=1, BZERO=0)
```

这里的“unsupported”是有意的能力边界：`parse_fits` 已经完整遍历并校验第三个 HDU 的结构；固定宽度表 API 只接受当前实现的 `A/L/X/B/I/J/K/E/D` 字段，因此对 `Q` 可变长度描述符给出明确错误，不会把 heap 数据误当成定宽单元。

## 2. Astropy 对照

Astropy 官方验证接口是 [`astropy.io.fits` verification](https://docs.astropy.org/en/stable/io/fits/usage/verification.html)。在安装 Astropy 的 Python 环境执行：

```text
py -3 -c "from astropy.io import fits; p='conformance/fixtures/test64bit1.fit'; h=fits.open(p, memmap=False); print('verify', h.verify('exception')); print('hdus', len(h)); print('primary', h[0].header['BITPIX'], tuple(h[0].header['NAXIS'+str(i)] for i in range(1, h[0].header['NAXIS']+1)), h[0].data.shape); [print('table', i, h[i].header['TFORM1'], h[i].header['TFORM2'], h[i].header['NAXIS1'], h[i].header['NAXIS2'], h[i].header['PCOUNT'], len(h[i].data)) for i in (1, 2)]; h.close()"
```

期望值：

```text
verify None
hdus 3
primary 64 (5, 3) (3, 5)
table 1 1J 1K 12 15 0 15
table 2 1J 1QK(15) 20 15 960 15
```

## 3. FITSverify 对照

FITSverify 是 HEASARC 提供的独立格式验证器；官方页面说明其当前版本为 4.22，并给出 `fitsverify filename.fits` 用法：<https://heasarc.gsfc.nasa.gov/docs/software/ftools/fitsverify/>。

本次在 Ubuntu 22.04 环境使用发行版 `fitsverify 4.20 (CFITSIO V4.000)` 执行：

```text
fitsverify /mnt/c/Users/27229/Desktop/nmoonbit/MoonAstroFITS/conformance/fixtures/test64bit1.fit
```

关键结果：

```text
3 Header-Data Units in this file.
HDU 1: Primary Array — 64-bit long integer pixels, 2 axes (5 x 3)
HDU 2: BINARY Table — 2 columns x 15 rows — 1J, 1K
HDU 3: BINARY Table — 2 columns x 15 rows — 1J, 1QK(15)
Verification found 0 warning(s) and 0 error(s).
```

## 4. 验收矩阵

| 断言 | Astropy | FITSverify | MoonAstroFITS |
| --- | --- | --- | --- |
| 文件长度 17,280 bytes | 通过 | 通过 | 通过 |
| 3 个 HDU，主图像 BITPIX=64、轴 5×3 | 通过 | 通过 | 通过并可解码 15 个样本 |
| 第 2 个 HDU 的 `1J + 1K` 定宽表 | 通过 | 0 warning / 0 error | 通过并可解码首行 2 个单元 |
| 第 3 个 HDU 的 `1QK(15)` 变长表 | 通过 | 0 warning / 0 error | 结构遍历通过；定宽表 API 明确报告不支持 |

因此本样例同时证明了“真实文件可读、结构边界与外部工具一致”和“暂未实现的 Q/heap 能力有可诊断的失败路径”。它不宣称 MoonAstroFITS 已经实现 `Q` 变长数组解码；后续若补上 heap API，应在同一夹具上增加逐行语义对比。
