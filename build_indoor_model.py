"""Build the real ADE20K indoor model into Flutter assets; fail closed.

Requires Python 3.12 on Linux/macOS (Core ML: macOS). Dependency version is
pinned in model-requirements.txt. No training or user images are uploaded.
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MODEL = 'yolo26n-sem-ade20k'
WEIGHTS_URL = f'https://github.com/ultralytics/assets/releases/download/v8.4.0/{MODEL}.pt'
WEIGHTS_SHA256 = '68ac71bef2868c987fff7cd7c49cb656922f6d8447ad21af3893305577435000'
EXPORTER_VERSION = '8.4.184'
SIZE = 640

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def validate_names(names):
    if isinstance(names, list):
        names = dict(enumerate(names))
    assert isinstance(names, dict), 'Missing actual model label metadata'
    labels = {int(k): str(v) for k, v in names.items()}
    assert set(labels) == set(range(150)), f'Expected ADE20K 150 labels; got {len(labels)}'
    assert {'door', 'wall', 'floor', 'ceiling', 'windowpane'} <= set(labels.values()), 'Wrong indoor categories'
    return labels

def tflite_metadata(path):
    with zipfile.ZipFile(path) as z:
        candidates = [i for i in z.infolist() if i.filename in
                      ('metadata.json', 'TFLITE_ULTRALYTICS_METADATA.json')]
        assert candidates, 'Export contains no embedded metadata'
        data = json.loads(z.read(candidates[-1]))
    assert data['task'] == 'semantic', 'Not a semantic model'
    validate_names(data['names'])
    return data

def verify_android(path):
    import numpy as np
    from ai_edge_litert.interpreter import Interpreter
    tflite_metadata(path)
    interpreter = Interpreter(model_path=str(path), num_threads=2)
    interpreter.allocate_tensors()
    inputs = interpreter.get_input_details()
    assert len(inputs) == 1
    detail = inputs[0]
    assert detail['shape'].tolist() in ([1, 3, SIZE, SIZE], [1, SIZE, SIZE, 3])
    assert detail['dtype'] == np.float32
    interpreter.set_tensor(detail['index'], np.zeros(detail['shape'], dtype=np.float32))
    interpreter.invoke()
    outputs = interpreter.get_output_details()
    assert len(outputs) == 1
    result = interpreter.get_tensor(outputs[0]['index'])
    assert result.ndim == 4 and result.shape[0] == 1 and 150 in result.shape[1:]
    assert np.isfinite(result).all(), 'Non-finite semantic output'
    return {'input': detail['shape'].tolist(), 'output': list(result.shape),
            'zero_input_inference': 'passed', 'accuracy_measured': False}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=['android', 'ios', 'both'], default='android')
    args = parser.parse_args()
    import ultralytics
    from ultralytics import YOLO
    assert ultralytics.__version__ == EXPORTER_VERSION
    work = ROOT / '.visioncane/model-export'
    assets = ROOT / 'assets/models'
    work.mkdir(parents=True, exist_ok=True)
    assets.mkdir(parents=True, exist_ok=True)
    weights = work / f'{MODEL}.pt'
    if not weights.exists() or digest(weights) != WEIGHTS_SHA256:
        temporary = weights.with_suffix('.download')
        with urllib.request.urlopen(WEIGHTS_URL, timeout=120) as response, temporary.open('wb') as out:
            shutil.copyfileobj(response, out)
        assert digest(temporary) == WEIGHTS_SHA256, 'Official checkpoint digest mismatch'
        temporary.replace(weights)
    os.chdir(work)
    model = YOLO(str(weights), task='semantic')
    labels = validate_names(model.names)
    report = {'model': MODEL, 'checkpoint_sha256': WEIGHTS_SHA256, 'exporter': EXPORTER_VERSION,
              'imgsz': SIZE, 'labels': labels, 'device_validated': False, 'platforms': {}}
    if args.platform in ('android', 'both'):
        dest = assets / 'visioncane-indoor-v1.tflite'
        cache = work / 'verified-android.json'
        cached = json.loads(cache.read_text()) if cache.exists() else {}
        if not dest.exists() or cached.get('sha256') != digest(dest) or cached.get('checkpoint') != WEIGHTS_SHA256:
            exported = Path(model.export(format='litert', quantize='w8a32', nms=None, imgsz=SIZE, batch=1))
            assert exported.is_file() and exported.suffix == '.tflite'
            verify_android(exported)
            shutil.copy2(exported, dest)
        verification = verify_android(dest)
        report['platforms']['android'] = {'sha256': digest(dest), **verification}
        cache.write_text(json.dumps({'sha256': digest(dest), 'checkpoint': WEIGHTS_SHA256}))
    if args.platform in ('ios', 'both'):
        import coremltools as ct
        from PIL import Image
        exported = Path(model.export(format='coreml', int8=True, nms=False, imgsz=SIZE, batch=1))
        assert exported.is_dir() and exported.suffix == '.mlpackage'
        core = ct.models.MLModel(str(exported))
        validate_names(ast.literal_eval(core.user_defined_metadata['names']))
        # Real inference on the Mac build host, not only a syntax check.
        input_name = core.get_spec().description.input[0].name
        result = core.predict({input_name: Image.new('RGB', (SIZE, SIZE))})
        import numpy as np
        assert any(np.asarray(v).ndim == 4 and 150 in np.asarray(v).shape for v in result.values())
        dest = assets / 'visioncane-indoor-v1.mlpackage.zip'
        with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as z:
            for file in exported.rglob('*'):
                if file.is_file(): z.write(file, Path('visioncane-indoor-v1.mlpackage') / file.relative_to(exported))
        report['platforms']['ios'] = {'sha256': digest(dest), 'zero_input_inference': 'passed', 'accuracy_measured': False}
    (assets / 'model-build.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'labels'}, indent=2))

if __name__ == '__main__':
    main()
