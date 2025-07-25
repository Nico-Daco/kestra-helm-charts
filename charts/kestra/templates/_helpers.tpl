{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "kestra.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kestra.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- printf "%s-%s" .Release.Name .Component | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s-%s" .Release.Name .Chart.Name .Component | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kestra.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "kestra.labels" -}}
app.kubernetes.io/name: {{ include "kestra.name" . }}
app.kubernetes.io/component: {{ .Component }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .WorkerGroup }}
app.kubernetes.io/worker-group: {{ .WorkerGroup }}
{{- end }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "kestra.chart" . }}
{{- end -}}


{{/*
Selectors labels
*/}}
{{- define "kestra.selectorsLabels" -}}
app.kubernetes.io/name: {{ include "kestra.name" . }}
app.kubernetes.io/component: {{ .Component }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}


{{/*
Form the Elasticsearch URL.
*/}}
{{- define "kestra.elasticsearch.url" }}
{{- $port := .Values.elasticsearch.httpPort | toString }}
{{- printf "%s://%s:%s" .Values.elasticsearch.protocol (include "elasticsearch.uname" (dict "Values" $.Values.elasticsearch)) $port }}
{{- end -}}

{{/*
Form the Kafka URL.
*/}}
{{- define "kestra.kafka.url" }}
{{- printf "%s-%s:%s" .Release.Name "kafka" "9092" -}}
{{- end -}}

{{/*
Form the Minio URL.
*/}}
{{- define "kestra.minio.url" }}
{{- printf "%s-%s" .Release.Name "minio" -}}
{{- end -}}

{{/*
Form the Postgres URL.
*/}}
{{- define "kestra.postgres.url" }}
{{- $port := $.Values.postgresql.primary.service.ports.postgresql | toString }}
{{- printf "%s-%s:%s" .Release.Name "postgresql" $port -}}
{{- end -}}

{{- define "kestra.vaultSecretPath" -}}
{{- $org := default "example.com" .Values.global.organisationDomainName -}}
{{- $proj := default "demo" .Values.global.projectName -}}
{{- $env := default "dev" .Values.global.environmentName -}}
{{- $bce := default "default" .Values.global.bconnectEnvironmentName -}}
{{- printf "%s/data/%s/%s/%s/" $org $proj $env $bce }}
{{- end }}

{{/*
k8s-config vars
*/}}
{{- define "kestra.k8s-config" -}}
{{- if .Values.postgresql.enabled }}
datasources:
  postgres:
    url: jdbc:postgresql://{{ include "kestra.postgres.url" . }}/{{ .Values.postgresql.auth.database }}
    driverClassName: org.postgresql.Driver
    username: {{ .Values.postgresql.auth.username }}
    password: {{ .Values.postgresql.auth.password }}
{{ end }}
{{- if or .Values.elasticsearch.enabled .Values.kafka.enabled .Values.postgresql.enabled .Values.minio.enabled -}}
kestra:
{{- if .Values.elasticsearch.enabled }}
  repository:
    type: elasticsearch
  elasticsearch:
    client:
      http-hosts: {{ include "kestra.elasticsearch.url" . }}
{{- end }}
{{- if .Values.kafka.enabled }}
  queue:
    type: kafka
  kafka:
    client:
      properties:
        bootstrap.servers: {{ include "kestra.kafka.url" . }}
{{- end }}
{{- if .Values.postgresql.enabled }}
  queue:
    type: postgres
  repository:
    type: postgres
{{- end }}
{{- if .Values.minio.enabled }}
  storage:
    type: minio
    minio:
      endpoint: {{ include "kestra.minio.url" . }}
      port: 9000
      access-key: {{ .Values.minio.auth.rootUser }}
      secret-key: {{ .Values.minio.auth.rootPassword }}
      secure: false
      bucket: kestra
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Env vars
*/}}
{{- define "kestra.configurationPath" -}}
{{- $configurations := list -}}

{{- if .Values.configurationPath -}}
{{- $configurations = append $configurations $.Values.configurationPath }}
{{- else }}
  {{- if $.Values.configuration }}{{ $configurations = append $configurations "/app/confs/application.yml" }}{{- end }}
  {{- if $.Values.secrets }}{{ $configurations = append $configurations "/app/secrets/application-secrets.yml" }}{{- end }}
  {{- if include "kestra.k8s-config" $ }}{{ $configurations = append $configurations "/app/secrets/application-k8s.yml" }}{{- end }}
  {{- if $.Values.externalSecret }}{{ $configurations = append $configurations "/app/secrets/external/application-secrets-external.yml" }}{{- end }}
{{- end -}}

- name: MICRONAUT_CONFIG_FILES
  value: {{ join "," $configurations }}

{{- end -}}


{{/*
Deployment template
*/}}
{{- define "kestra.deployment" -}}
{{- $name := .Name -}}
{{- $type := .Type -}}
{{- $deployment := .Deployment -}}
{{- $merged := (merge (dict "Component" $name) $) -}}
{{- $dind := and ($.Values.dind.enabled) (or (eq $type "worker") (eq $type "standalone")) -}}
apiVersion: apps/v1
kind: {{ $deployment.kind }}
metadata:
  name: {{ include "kestra.fullname" $merged }}
  labels:
    {{- include "kestra.labels" $merged | nindent 4 }}
    {{- with $deployment.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    {{- with $.Values.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- with $deployment.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  {{- if eq $deployment.kind "Deployment" }}
  replicas: {{ $deployment.replicaCount | default 1 }}
  {{- end }}
  {{- if $deployment.strategy }}
  strategy:
    {{- toYaml $deployment.strategy | nindent 4 }}
    {{ if eq $deployment.strategy.type "Recreate" }}rollingUpdate: null{{ end }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "kestra.selectorsLabels" $merged | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "kestra.selectorsLabels" $merged | nindent 8 }}
        {{- with $deployment.labels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}

      annotations:
        checksum/secrets: {{ include (print $.Template.BasePath "/secret.yaml") $ | sha256sum }}
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") $ | sha256sum }}
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "{{ .Release.Namespace }}"
        vault.hashicorp.com/agent-inject-secret-kestra-internal: |-
          "{{ include "kestra.vaultSecretPath" $ }}"kestra-internal

        vault.hashicorp.com/agent-inject-secret-kestra-worker: |-
          "{{ include "kestra.vaultSecretPath" $ }}"kestra-worker

        vault.hashicorp.com/agent-inject-template-kestra-internal: |-
          {{`{{- with secret `}}"{{ include "kestra.vaultSecretPath" $ }}kestra-internal"{{` -}}`}}
          {{`{{- range $k, $v := .Data.data }}`}}
          {{`export {{ $k }}='{{ $v }}'`}}
          {{`{{- end }}`}}
          {{`{{- end }}`}}

        vault.hashicorp.com/agent-inject-template-kestra-worker: |-
          {{`{{- with secret `}}"{{ include "kestra.vaultSecretPath" $ }}kestra-worker"{{` -}}`}}
          {{`{{- range $k, $v := .Data.data }}`}}
          {{`export {{ $k }}='{{ $v }}'`}}
          {{`{{- end }}`}}
          {{`{{- end }}`}}
      {{- with $.Values.podAnnotations }}
      {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      {{- if $.Values.serviceAccountName }}
      serviceAccountName: {{ $.Values.serviceAccountName }}
      {{- end }}
      {{- with $.Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if $.Values.initContainers }}
      initContainers:
      {{- toYaml $.Values.initContainers | nindent 8 }}
      {{- end }}
      terminationGracePeriodSeconds: {{ default $.Values.terminationGracePeriodSeconds $deployment.terminationGracePeriodSeconds }}
      {{- if $dind }}
      securityContext:
      {{- toYaml (default $.Values.podSecurityContext $deployment.podSecurityContext) | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ $.Chart.Name }}-{{ $name }}
          securityContext:
          {{- toYaml (default $.Values.securityContext $deployment.securityContext) | nindent 12 }}
          image: "{{ $.Values.image.image }}:{{ $.Values.image.tag | default $.Chart.AppVersion }}"
          imagePullPolicy: {{ $.Values.image.pullPolicy }}
          command:
            - sh
            - -c
            - "source /vault/secrets/kestra-internal && source /vault/secrets/kestra-worker && {{ $.Values.executable }} {{ tpl $deployment.command $ }}"
          env:
            {{- with default $.Values.extraEnv $deployment.extraEnv }}
            {{- toYaml . | trim | nindent 12 }}
            {{- end }}
            {{- include "kestra.configurationPath" $ | nindent 12 }}
          {{- if or .Values.extraConfigMapEnvFrom .Values.extraSecretEnvFrom }}
          envFrom:
          {{- end }}
            {{- with .Values.extraConfigMapEnvFrom }}
            {{- range . }}
            - configMapRef:
                name: {{ .name }}
            {{- if .prefix }}
              prefix: {{ .prefix }}
            {{- end }}
            {{- end }}
            {{- end }}
            {{- with .Values.extraSecretEnvFrom }}
            {{- range . }}
            - secretRef:
                name: {{ .name }}
            {{- if .prefix }}
              prefix: {{ .prefix }}
            {{- end }}
            {{- end }}
            {{- end }}
          volumeMounts:
            {{- if $.Values.extraVolumeMounts }}{{ toYaml $.Values.extraVolumeMounts | trim | nindent 12 }}{{ end }}
            {{- if $.Values.configuration }}
            - name: config
              mountPath: /app/confs/
            {{- end }}
            {{- if or $.Values.secrets (include "kestra.k8s-config" $) }}
            - name: secrets
              mountPath: /app/secrets/
            {{- end }}
            {{- if $.Values.externalSecret }}
            - name: external-secret
              mountPath: /app/secrets/external/
            {{- end }}

            {{- if $dind }}
            - name: docker-dind-socket
              mountPath: /dind
            - name: docker-tmp
              mountPath: {{ $.Values.dind.tmpPath }}
            {{- end }}
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
            - name: management
              containerPort: 8081
              protocol: TCP
            {{- if $.Values.extraPorts }}{{ toYaml $.Values.extraPorts | trim | nindent 12 }}{{ end }}
          {{- if or $.Values.startupProbe.enabled $deployment.startupProbe.enabled }}
          {{- $startupProbe := merge (or $deployment.startupProbe dict) $.Values.startupProbe }}
          startupProbe:
            {{- if $startupProbe.httpGetEnabled }}
            httpGet:
              path: {{ $startupProbe.path }}
              port: {{ $startupProbe.port }}
              {{- with $startupProbe.httpGetExtra }}
              {{ toYaml . | nindent 14  }}
              {{- end }}
            {{- end }}
            {{- with $startupProbe.exec }}
            exec: {{- toYaml . | nindent 4 }}
            {{- end }}
            initialDelaySeconds: {{ $startupProbe.initialDelaySeconds }}
            periodSeconds: {{ $startupProbe.periodSeconds }}
            timeoutSeconds: {{ $startupProbe.timeoutSeconds }}
            successThreshold: {{ $startupProbe.successThreshold }}
            failureThreshold: {{ $startupProbe.failureThreshold }}
          {{- end }}
          {{- if or $.Values.livenessProbe.enabled $deployment.livenessProbe.enabled }}
          {{- $livenessProbe := merge (or $deployment.livenessProbe dict) $.Values.livenessProbe }}
          livenessProbe:
            {{- if $livenessProbe.httpGetEnabled }}
            httpGet:
              path: {{ $livenessProbe.path }}
              port: {{ $livenessProbe.port }}
              {{- with $livenessProbe.httpGetExtra }}
              {{- toYaml . | nindent 14 }}
              {{- end }}
            {{- end }}
            {{- with $livenessProbe.exec }}
            exec: {{- toYaml . | nindent 4 }}
            {{- end }}
            initialDelaySeconds: {{ $livenessProbe.initialDelaySeconds }}
            periodSeconds: {{ $livenessProbe.periodSeconds }}
            timeoutSeconds: {{ $livenessProbe.timeoutSeconds }}
            successThreshold: {{ $livenessProbe.successThreshold }}
            failureThreshold: {{ $livenessProbe.failureThreshold }}
          {{- end }}
          {{- if or $.Values.readinessProbe.enabled $deployment.readinessProbe.enabled }}
          {{- $readinessProbe := merge (or $deployment.readinessProbe dict) $.Values.readinessProbe }}
          readinessProbe:
            {{- if $readinessProbe.httpGetEnabled }}
            httpGet:
              path: {{ $readinessProbe.path }}
              port: {{ $readinessProbe.port }}
              {{- with $readinessProbe.httpGetExtra }}
              {{- toYaml . | nindent 14 }}
              {{- end }}
            {{- end }}
            {{- with $readinessProbe.exec }}
            exec: {{- toYaml . | nindent 4 }}
            {{- end }}
            initialDelaySeconds: {{ $readinessProbe.initialDelaySeconds }}
            periodSeconds: {{ $readinessProbe.periodSeconds }}
            timeoutSeconds: {{ $readinessProbe.timeoutSeconds }}
            successThreshold: {{ $readinessProbe.successThreshold }}
            failureThreshold: {{ $readinessProbe.failureThreshold }}
          {{- end }}
          resources:
            {{- toYaml (default $.Values.resources $deployment.resources) | nindent 12 }}
        {{- if $dind }}
        - name: {{ $.Chart.Name }}-{{ $name }}-docker-dind
          image: "{{ $.Values.dind.image.image }}:{{ $.Values.dind.image.tag }}"
          imagePullPolicy: {{ $.Values.dind.image.pullPolicy }}
          command: |
            source /vault/secrets/kestra-internal && source /vault/secrets/kestra-worker && dockerd-entrypoint.sh
          args:
            {{- toYaml $.Values.dind.args | nindent 12 }}
          env:
            {{- if $.Values.dind.extraEnv }}{{ toYaml $.Values.dind.extraEnv | trim | nindent 12 }}{{ end }}
            - name: DOCKER_HOST
              value: unix://{{ $.Values.dind.socketPath }}/docker.sock
          securityContext:
            privileged: true
            {{- if $.Values.dind.securityContext }}
            {{- toYaml $.Values.dind.securityContext | nindent 12 }}
            {{- end }}
          volumeMounts:
            {{- if $.Values.dind.extraVolumeMounts }}{{ toYaml $.Values.dind.extraVolumeMounts | trim | nindent 12 }}{{ end }}
            - name: docker-dind-socket
              mountPath: {{ $.Values.dind.socketPath }}
            - name: docker-tmp
              mountPath: {{ $.Values.dind.tmpPath }}
          resources:
            {{- toYaml $.Values.dind.resources | nindent 12 }}
        {{- end }}
        {{- with default $.Values.extraContainers $deployment.extraContainers }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with default $.Values.nodeSelector $deployment.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with default $.Values.affinity $deployment.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with default $.Values.tolerations $deployment.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      volumes:
        {{- if $.Values.extraVolumes }}{{ toYaml $.Values.extraVolumes | trim | nindent 8 }}{{ end }}
        {{- if $.Values.configuration }}
        - name: config
          configMap:
            name: {{ template "kestra.fullname" (merge (dict "Component" "configmap") $) }}
            items:
              {{- if $.Values.configuration }}
              - key: application.yml
                path: application.yml
              {{- end }}
        {{- end }}
        {{- if or $.Values.secrets (include "kestra.k8s-config" $) }}
        - name: secrets
          secret:
            secretName: {{ template "kestra.fullname" (merge (dict "Component" "secret") $) }}
            items:
            {{- if $.Values.secrets }}
              - key: application-secrets.yml
                path: application-secrets.yml
            {{- end }}
            {{- if (include "kestra.k8s-config" $) }}
              - key: application-k8s.yml
                path: application-k8s.yml
            {{- end }}
        {{- end }}
        {{- if $.Values.externalSecret }}
        - name: external-secret
          secret:
            secretName: {{ $.Values.externalSecret.secretName }}
            items:
              - key: {{ $.Values.externalSecret.key }}
                path: application-secrets-external.yml
        {{- end }}
        {{- if $dind }}
        - name: docker-dind-socket
          emptyDir: {}
        - name: docker-tmp
          emptyDir: {}
        {{- end }}
{{- end -}}


{{/*
Renders a value that contains template.
Usage:
{{ include "kestra.extra-render" ( dict "value" .Values.path.to.the.Value "context" $) }}
*/}}
{{- define "kestra.extra-render" -}}
    {{- if typeIs "string" .value }}
        {{- tpl .value .context }}
    {{- else }}
        {{- tpl (.value | toYaml) .context }}
    {{- end }}
{{- end -}}
