#!/usr/bin/env python

import argparse
import json
import re

def run(args, env_config, secrets_config):
    pipeline_tools_prefix = args.pipeline_tools_prefix
    tenx_prefix = args.tenx_prefix
    ss2_prefix = args.ss2_prefix

    config = {
        'env': env_config['env'],
        'cromwell_url': 'https://cromwell.mint-{0}.broadinstitute.org/api/workflows/v1'.format(env_config['env']),
        'MAX_CONTENT_LENGTH': 10000,
        'submit_wdl': '{0}/adapter_pipelines/submit.wdl'.format(pipeline_tools_prefix),
    }
    config.update(secrets_config)

    wdl_config = {
      'wdls': [
        {
          'subscription_id': env_config['10x_subscription_id'],
          'workflow_name': 'Wrapper10xCount',
          'analysis_wdl': '{0}/10x/count/count.wdl'.format(tenx_prefix),
          'wdl_link': '{0}/adapter_pipelines/10x/adapter.wdl'.format(pipeline_tools_prefix),
          'wdl_default_inputs_link': '{0}/adapter_pipelines/10x/adapter_example_static.json'.format(pipeline_tools_prefix),
          'options_link': '{0}/adapter_pipelines/10x/options.json'.format(pipeline_tools_prefix)
        },
        {
          'subscription_id': env_config['ss2_subscription_id'],
          'workflow_name': 'WrapperSs2RsemSingleSample',
          'analysis_wdl': '{0}/smartseq2_single_sample/ss2_single_sample.wdl'.format(ss2_prefix),
          'wdl_link': '{0}/adapter_pipelines/smart_seq2/adapter.wdl'.format(pipeline_tools_prefix),
          'wdl_default_inputs_link': '{0}/adapter_pipelines/smart_seq2/adapter_example_static_demo.json'.format(pipeline_tools_prefix),
          'options_link': '{0}/adapter_pipelines/smart_seq2/options.json'.format(pipeline_tools_prefix)
        }
      ]
    }
    config.update(wdl_config)
    print(json.dumps(config, indent=2, sort_keys=True))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--env_config_file', required=True)
    parser.add_argument('--secrets_file', required=True)
    parser.add_argument('--pipeline_tools_prefix', required=True)
    parser.add_argument('--tenx_prefix', required=True)
    parser.add_argument('--ss2_prefix', required=True)
    args = parser.parse_args()

    with open(args.env_config_file) as f:
        env_config = json.load(f)
    with open(args.secrets_file) as f:
        secrets_config = json.load(f)

    run(args, env_config, secrets_config)


