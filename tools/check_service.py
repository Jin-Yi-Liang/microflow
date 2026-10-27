#!/usr/bin/env python3
"""验证真实 HTTP 页面、模型推理和特征图；不使用系统代理，不修改模型。"""
import json
import struct
import sys
import time
import urllib.error
import urllib.request


def check(base, sample_path, threads):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def request(path, payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        req = urllib.request.Request(base.rstrip('/') + path, data=data,
                                     headers={'Content-Type': 'application/json'})
        with opener.open(req, timeout=5) as response:
            return response.read()

    last = None
    for _ in range(20):
        try:
            health = json.loads(request('/health'))
            if health.get('status') != 'ok' or health.get('threads') != threads:
                raise ValueError('健康状态或线程数不符')
            break
        except (OSError, ValueError, urllib.error.URLError) as error:
            last = error
            time.sleep(.25)
    else:
        raise RuntimeError(f'服务尚未健康：{last}')
    if b'MicroFlow' not in request('/'):
        raise ValueError('主页不是 MicroFlow 页面')
    with open(sample_path, 'rb') as sample:
        raw = sample.read()
    if len(raw) != 784 * 4:
        raise ValueError('内置手写 7 样本必须为 784 个 float32')
    pixels = list(struct.unpack('<784f', raw))
    result = json.loads(request('/predict', {'pixels': pixels}))
    if result.get('digit') != 7 or len(result.get('scores', [])) != 10:
        raise ValueError(f'真实手写 7 的预测不符：{result}')
    features = json.loads(request('/visualize', {'pixels': pixels}))
    if features.get('digit') != 7:
        raise ValueError('特征图接口未返回正确数字')
    try:
        request('/predict', {'pixels': [0]})
    except urllib.error.HTTPError as error:
        if error.code != 400:
            raise
    else:
        raise ValueError('非法输入未被 HTTP 400 拒绝')
    print(f'HTTP 验收通过：主页、健康、手写 7、特征图、非法输入拒绝；confidence={result["confidence"]:.6f}')


if __name__ == '__main__':
    try:
        check(sys.argv[1], sys.argv[2], int(sys.argv[3]))
    except (OSError, ValueError, RuntimeError, IndexError, urllib.error.URLError) as error:
        print(f'HTTP 验收失败：{error}', file=sys.stderr)
        sys.exit(1)
