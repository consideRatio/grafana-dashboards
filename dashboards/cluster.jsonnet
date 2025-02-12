// Deploys a dashboard showing cluster-wide information
local grafana = import '../vendor/grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local graphPanel = grafana.graphPanel;
local prometheus = grafana.prometheus;
local template = grafana.template;
local row = grafana.row;

local jupyterhub = import './jupyterhub.libsonnet';
local standardDims = jupyterhub.standardDims;

local templates = [
  template.datasource(
    name='PROMETHEUS_DS',
    query='prometheus',
    current=null,
    hide='label',
  ),
];

// Cluster-wide stats
local userNodes = graphPanel.new(
  'Node Count',
  decimals=0,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTarget(
  prometheus.target(
    |||
      # sum up all nodes by nodepool
      sum(
        # kube_pod_labels comes from
        # https://github.com/kubernetes/kube-state-metrics, and there is a particular
        # label (kubernetes_node) that lists the node on which the kube-state-metrics pod
        # s running! So that's totally irrelevant to these queries, but when a nodepool
        # is rotated it caused there to exist two metrics with the same node value (which
        # we care about) but different kubernetes_node values (because kube-state-metrics
        # was running in a different node, even though we don't care about that). This
        # group really just drops all labels except the two we care about to
        # avoid messing things up.
        group(
          kube_node_labels
        ) by (node, label_cloud_google_com_gke_nodepool)
      ) by (label_cloud_google_com_gke_nodepool)
    |||,
    legendFormat='{{label_cloud_google_com_gke_nodepool}}'
  ),
);

local userPods = graphPanel.new(
  'Running Users',
  description=|||
    Count of running users, grouped by namespace
  |||,
  decimals=0,
  min=0,
  stack=true,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      # Sum up all running user pods by namespace
      sum(
        # Grab a list of all running pods.
        # The group aggregator always returns "1" for the number of times each
        # unique label appears in the time series. This is desirable for this
        # use case because we're merely identifying running pods by name,
        # not how many times they might be running.
        group(
          kube_pod_status_phase{phase="Running"}
        ) by (pod)
        * on (pod) group_right() group(
          kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server"}
        ) by (namespace, pod)
      ) by (namespace)
    |||,
    legendFormat='{{namespace}}'
  ),
]);

local clusterMemoryCommitment = graphPanel.new(
  'Memory commitment %',
  formatY1='percentunit',
  description=|||
    % of total memory in the cluster currently requested by to non-placeholder pods.

    If autoscaling is efficient, this should be a fairly constant, high number (>70%).
  |||,
  min=0,
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        # Get individual container memory requests
        kube_pod_container_resource_requests{resource="memory"}
        # Add node pool name as label
        * on(node) group_left(label_cloud_google_com_gke_nodepool)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, label_cloud_google_com_gke_nodepool)
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (label_cloud_google_com_gke_nodepool)
      /
      sum(
        # Total allocatable memory on a node
        kube_node_status_allocatable{resource="memory"}
        # Add nodepool name as label
        * on(node) group_left(label_cloud_google_com_gke_nodepool)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, label_cloud_google_com_gke_nodepool)
      ) by (label_cloud_google_com_gke_nodepool)
    |||,
    legendFormat='{{label_cloud_google_com_gke_nodepool}}'
  ),
]);

local clusterCPUCommitment = graphPanel.new(
  'CPU commitment %',
  formatY1='percentunit',
  description=|||
    % of total CPU in the cluster currently requested by to non-placeholder pods.

    JupyterHub users mostly are capped by memory, so this is not super useful.
  |||,
  min=0,
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        # Get individual container memory requests
        kube_pod_container_resource_requests{resource="cpu"}
        # Add node pool name as label
        * on(node) group_left(label_cloud_google_com_gke_nodepool)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, label_cloud_google_com_gke_nodepool)
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (label_cloud_google_com_gke_nodepool)
      /
      sum(
        # Total allocatable CPU on a node
        kube_node_status_allocatable{resource="cpu"}
        # Add nodepool name as label
        * on(node) group_left(label_cloud_google_com_gke_nodepool)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, label_cloud_google_com_gke_nodepool)
      ) by (label_cloud_google_com_gke_nodepool)
    |||,
    legendFormat='{{label_cloud_google_com_gke_nodepool}}'
  ),
]);


local nodeCPUCommit = graphPanel.new(
  'Node CPU Commit %',
  formatY1='percentunit',
  description=|||
    % of each node guaranteed to pods on it
  |||,
  min=0,
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        # Get individual container CPU limits
        kube_pod_container_resource_requests{resource="cpu"}
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (node)
      /
      sum(
        # Get individual container CPU requests
        kube_node_status_allocatable{resource="cpu"}
      ) by (node)
    |||,
    legendFormat='{{node}}'
  ),
]);

local nodeMemoryCommit = graphPanel.new(
  'Node Memory Commit %',
  formatY1='percentunit',
  description=|||
    % of each node guaranteed to pods on it
  |||,
  min=0,
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        # Get individual container memory limits
        kube_pod_container_resource_requests{resource="memory"}
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (node)
      /
      sum(
        # Get individual container memory requests
        kube_node_status_allocatable{resource="memory"}
      ) by (node)
    |||,
    legendFormat='{{node}}'
  ),
]);

// Cluster diagnostics
local nodeMemoryUtil = graphPanel.new(
  'Node Memory Utilization %',
  formatY1='percentunit',
  description=|||
    % of available Memory currently in use
  |||,
  min=0,
  // since this is actual measured utilization, it should not be able to exceed max=1
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      1 - (
        sum (
          # Memory that can be allocated to processes when they need
          node_memory_MemFree_bytes + # Unused bytes
          node_memory_Cached_bytes + # Shared memory + temporary disk cache
          node_memory_Buffers_bytes # Very temporary buffer memory cache for disk i/o
        ) by (node)
        /
        sum(node_memory_MemTotal_bytes) by (node)
      )
    |||,
    legendFormat='{{node}}'
  ),
]);

local nodeCPUUtil = graphPanel.new(
  'Node CPU Utilization %',
  formatY1='percentunit',
  description=|||
    % of available CPUs currently in use
  |||,
  min=0,
  // since this is actual measured utilization, it should not be able to exceed max=1
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (node)
      /
      sum(kube_node_status_capacity{resource="cpu"}) by (node)
    |||,
    legendFormat='{{ node }}'
  ),
]);


local nonRunningPods = graphPanel.new(
  'Non Running Pods',
  description=|||
    Pods in states other than 'Running'.

    In a functional clusters, pods should not be in non-Running states for long.
  |||,
  decimals=0,
  legend_hideZero=true,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(kube_pod_status_phase{phase!="Running"}) by (phase)',
    legendFormat='{{phase}}',
  ),
]);


dashboard.new(
  'Cluster Information',
  tags=['jupyterhub', 'kubernetes'],
  editable=true
).addTemplates(
  templates
).addPanel(
  row.new('Cluster Stats'), {},
).addPanel(
  userPods, { w: standardDims.w * 2 },
).addPanel(
  clusterMemoryCommitment, {},
).addPanel(
  clusterCPUCommitment, {},
).addPanel(
  userNodes, {},
).addPanel(
  nonRunningPods, {},

).addPanel(
  row.new('Node Stats'), {},
).addPanel(
  nodeCPUUtil, {},
).addPanel(
  nodeMemoryUtil, {},
).addPanel(
  nodeCPUCommit, {},
).addPanel(
  nodeMemoryCommit, {},
)
