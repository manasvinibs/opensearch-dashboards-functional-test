/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import { App } from 'octokit';

async function triggerWorkflow() {
  const app = new App({
    appId: '810560',
    privateKey: process.env.GITHUB_TOKEN,
  });

  try {
    const response = await app.octokit.request(
      'POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches',
      {
        owner: 'manasvinibs',
        repo: 'Opensearch-Dashboards',
        workflow_id: 'dashboards_cypress_workflow.yml',
        ref: 'POC',
        inputs: {
          OS_URL: 'Mona the Octocat',
          OSD_URL: 'San Francisco, CA',
          build_id: '10000',
          UNIQUE_ID: '11111',
        },
        headers: {
          'X-GitHub-Api-Version': '2022-11-28',
        },
      }
    );
    console.log('logging octokit rest api resonse: ');
    console.log(response.data); // Assuming you want to log the response data
  } catch (error) {
    console.log('Encountered error on octokit request');
    console.error(error);
  }
}

// Call the async function
triggerWorkflow();
