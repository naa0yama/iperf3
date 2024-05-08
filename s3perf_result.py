#!/usr/bin/env python3
# To add a new cell, type '# %%'
# To add a new markdown cell, type '# %% [markdown]'
# %%
"""s3perf result."""
import glob
import json
import os
import datetime

__file_paths = glob.glob('logs/*/*.json')
JST = datetime.timezone(datetime.timedelta(hours=+9), 'JST')

_data_list: list = []
print(f"| filename  | region  | testcase  |type   | min | avg | max | start time | end time | elapsedTime |")
print(f"|:----------|:--------|:----------|:------|----:|----:|----:|-----------:|---------:|------------:|")

for _file in __file_paths:
    with open(_file) as f:
        jsonl_data = [json.loads(l) for l in f.readlines()]

    _filename_split: list = os.path.split(_file)[1].split('-')
    _region: str = _filename_split[3]
    _testcase: str = _filename_split[4]
    _pid: int = _filename_split[5]
    _type: str = _filename_split[6].split('.')[0]
    _filename: str = os.path.split(_file)[1].split('.')[0]
    _data: dict = {
        "filename": _filename,
        "region": _region,
        "testcase": _testcase,
        "type": _type,
        "pid": _pid,
        "elapsedTime": {
            "unit": "second",
            "data": []
        },
        "speed": {
            "unit": "MiB/s",
            "data": [],
        },
        "timestamp": {
            "unit": "unixtime",
            "data": [],
        },
    }
    for __json in jsonl_data:
        if __json["source"] == "accounting/stats.go:526":
            __stats: dict = __json['stats']
            _data['elapsedTime']['data'].append(round(__stats['elapsedTime']))
            _data['speed']['data'].append(__stats['speed'] /1024 /1024)

            _timedate: datetime = datetime.datetime.strptime(__json['time'], '%Y-%m-%dT%H:%M:%S.%f%z').astimezone(JST)
            _data['timestamp']['data'].append(_timedate.timestamp())

    _data['time_start'] = datetime.datetime.fromtimestamp(min(_data['timestamp']['data'])).strftime('%m/%d %H:%M:%S')
    _data['time_end'] = datetime.datetime.fromtimestamp(max(_data['timestamp']['data'])).strftime('%m/%d %H:%M:%S')
    _data['elapsedTime'] = f"{datetime.timedelta(seconds=max(_data['elapsedTime']['data']))}"
    _data['speed']["min"] = f"{min(_data['speed']['data']):.2f}"
    _data['speed']["avg"] = f"{sum(_data['speed']['data']) / len(_data['speed']['data']):.2f}"
    _data['speed']["max"] = f"{max(_data['speed']['data']):.2f}"
    _data_list.append(_data)

_data_list = sorted(_data_list, key=lambda x: x['time_start'])
for result in _data_list:
    _filename = result['filename']
    _region = result['region']
    _testcase = result['testcase']
    _type = result['type']
    _time_start = result['time_start']
    _time_end = result['time_end']
    _elapsedTime = result['elapsedTime']
    _speed_min = result['speed']['min']
    _speed_avg = result['speed']['avg']
    _speed_max = result['speed']['max']

    print(f"|{_filename}|{_region}|{_testcase}|{_type}| {_speed_min} | {_speed_avg} | {_speed_max} | {_time_start} | {_time_end} | {_elapsedTime} |")

__groups = {}
for result in _data_list:
    __regions: list = [
        "sg", "sj22", "la",
        "ph12", "or4", "da",
        "ch", "va", "ca",
        "mi", "ldn", "par",
        "ie", "fra",
    ]

    for ___region in __regions:
        if result['region'] == ___region:
            if ___region not in __groups:
                __groups[___region] = {
                    "region": ___region,
                    "speed": {
                        "min": 0,
                        "avg": 0,
                        "max": 0,
                    }
                }
            __groups[___region]['speed']['min'] = float(__groups[___region]['speed']['min']) + float(result['speed']['min'])
            __groups[___region]['speed']['avg'] = float(__groups[___region]['speed']['avg']) + float(result['speed']['avg'])
            __groups[___region]['speed']['max'] = float(__groups[___region]['speed']['max']) + float(result['speed']['max'])

print(f"| region | min MiB/s | avg MiB/s | max MiB/s|")
print(f"|:-------|----:|----:|----:|")

__groups_list: list = []
for ___region in __regions:
    __groups_list.append(
        {
            "region": __groups[___region]['region'],
            "speed": {
                "min": f"{__groups[___region]['speed']['min']/3:.2f}",
                "avg": f"{__groups[___region]['speed']['avg']/3:.2f}",
                "max": f"{__groups[___region]['speed']['max']/3:.2f}",
            }
        }
    )

    print(f"|{__groups[___region]['region']}|{__groups[___region]['speed']['min']/3:.2f}|{__groups[___region]['speed']['avg']/3:.2f}|{__groups[___region]['speed']['max']/3:.2f}|")

# num = 10
# while num < 7200:
#     print(f"'{datetime.timedelta(seconds=num)}'",end=', ')
#     num += 10
#
# print("End")

with open('results.json', 'w') as f:
    json.dump(_data_list, f, indent=2)

# %%
