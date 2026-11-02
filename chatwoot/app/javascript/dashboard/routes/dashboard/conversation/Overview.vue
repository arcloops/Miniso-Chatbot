<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import ConversationApi from 'dashboard/api/inbox/conversation';
import ContactAPI from 'dashboard/api/contacts';
import ReportsAPI from 'dashboard/api/reports';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const router = useRouter();
const store = useStore();
const currentUser = useMapGetter('getCurrentUser');
const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');

const loading = ref(true);
const counts = ref({
  open: null,
  pending: null,
  resolved: null,
  unassigned: null,
  contacts: null,
});
const openChats = ref([]);
const activity = ref([]);
const series = ref([]);
const summary = ref(null);
const previousSummary = ref(null);
const inboxCounts = ref({});
const agentCounts = ref({});

const today = new Date().toLocaleDateString(undefined, {
  weekday: 'long',
  month: 'long',
  day: 'numeric',
});

const firstName = computed(() => {
  const name = currentUser.value?.name || currentUser.value?.available_name || '';
  return name.split(' ')[0] || name;
});

const availability = computed(() => ({
  online: agents.value.filter(agent => agent.availability_status === 'online'),
  busy: agents.value.filter(agent => agent.availability_status === 'busy'),
  offline: agents.value.filter(agent => agent.availability_status === 'offline'),
}));

const workload = computed(() => {
  const rows = agents.value.map(agent => ({
    id: agent.id,
    name: agent.name || agent.available_name,
    status: agent.availability_status,
    count: agentCounts.value[agent.id] || 0,
  }));
  const max = Math.max(1, ...rows.map(row => row.count));
  return rows
    .sort((a, b) => b.count - a.count)
    .slice(0, 6)
    .map(row => ({ ...row, width: `${Math.round((row.count / max) * 100)}%` }));
});

const channels = computed(() =>
  inboxes.value.map(inbox => ({
    id: inbox.id,
    name: inbox.name,
    type: inbox.channel_type,
    icon: getInboxIconByType(inbox.channel_type, inbox.medium, 'line'),
    count: Object.prototype.hasOwnProperty.call(inboxCounts.value, inbox.id)
      ? inboxCounts.value[inbox.id]
      : null,
  }))
);

const chartPoints = computed(() => {
  const values = series.value.map(point => Number(point.value) || 0);
  if (!values.length) return '';
  const max = Math.max(...values, 1);
  const width = 280;
  const height = 88;
  return values
    .map((value, index) => {
      const x = values.length === 1 ? width / 2 : (index / (values.length - 1)) * width;
      const y = height - (value / max) * (height - 8) - 4;
      return `${x},${y}`;
    })
    .join(' ');
});

const responseLabel = computed(() => {
  const seconds = Number(summary.value?.avg_first_response_time);
  if (!Number.isFinite(seconds)) return null;
  if (seconds < 60) return `${Math.round(seconds)}s`;
  return `${Math.round(seconds / 60)}m`;
});

const trend = computed(() => {
  const current = Number(summary.value?.conversations_count);
  const previous = Number(previousSummary.value?.conversations_count);
  if (!Number.isFinite(current) || !Number.isFinite(previous) || previous === 0) return null;
  const change = Math.round(((current - previous) / previous) * 100);
  return { change, up: change >= 0 };
});

const range = () => {
  const until = Math.floor(Date.now() / 1000);
  const since = until - 6 * 24 * 60 * 60;
  return { since, until, previousSince: since - 7 * 24 * 60 * 60 };
};

const countFor = async status => {
  const { data } = await ConversationApi.meta({ status });
  return data?.meta || {};
};

const load = async () => {
  loading.value = true;
  const { since, until, previousSince } = range();
  const [openMeta, pendingMeta, resolvedMeta, contactPage, openPage, resolvedPage] =
    await Promise.all([
      countFor('open').catch(() => ({})),
      countFor('pending').catch(() => ({})),
      countFor('resolved').catch(() => ({})),
      ContactAPI.get(1).catch(() => null),
      ConversationApi.get({ status: 'open', page: 1, sortBy: 'last_activity_at_desc' }).catch(() => null),
      ConversationApi.get({ status: 'resolved', page: 1, sortBy: 'last_activity_at_desc' }).catch(() => null),
    ]);

  counts.value = {
    open: openMeta.all_count ?? null,
    pending: pendingMeta.all_count ?? null,
    resolved: resolvedMeta.all_count ?? null,
    unassigned: openMeta.unassigned_count ?? null,
    contacts: contactPage?.data?.meta?.count ?? null,
  };
  openChats.value = (openPage?.data?.data?.payload || []).slice(0, 6);
  const resolvedChats = (resolvedPage?.data?.data?.payload || []).slice(0, 4);
  activity.value = [...openChats.value, ...resolvedChats]
    .sort((a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0))
    .slice(0, 6);

  await Promise.all([
    store.dispatch('agents/get').catch(() => null),
    store.dispatch('inboxes/get').catch(() => null),
    ReportsAPI.getSummary(since, until).then(response => {
      summary.value = response.data;
    }).catch(() => null),
    ReportsAPI.getSummary(previousSince, since).then(response => {
      previousSummary.value = response.data;
    }).catch(() => null),
    ReportsAPI.getReports({
      metric: 'conversations_count',
      from: since,
      to: until,
      groupBy: 'day',
    }).then(response => {
      series.value = Array.isArray(response.data) ? response.data : [];
    }).catch(() => null),
    ReportsAPI.getInboxReports({ from: since, to: until }).then(response => {
      const rows = Array.isArray(response.data) ? response.data : [];
      inboxCounts.value = Object.fromEntries(rows.map(row => [row.id, row.conversations_count]));
    }).catch(() => null),
    ReportsAPI.getAgentReports({ from: since, to: until }).then(response => {
      const rows = Array.isArray(response.data) ? response.data : [];
      agentCounts.value = Object.fromEntries(rows.map(row => [row.id, row.conversations_count]));
    }).catch(() => null),
  ]);
  loading.value = false;
};

const openConversation = id => {
  router.push({ name: 'inbox_conversation', params: { conversation_id: id } });
};

const preview = chat => {
  const message = chat.messages?.[0]?.content || chat.additional_attributes?.mail_subject || '';
  return message || 'No message yet';
};

const senderName = chat => chat.meta?.sender?.name || 'Unknown';

onMounted(load);
</script>

<template>
  <section class="overview">
    <header class="overview-head">
      <div>
        <p class="eyebrow">{{ today }}</p>
        <h1>Good to see you, {{ firstName }}</h1>
        <p class="lede">
          A live look at the conversations, people, and channels already in this workspace.
        </p>
      </div>
      <div class="quick">
        <button type="button" @click="router.push({ name: 'home' })">All conversations</button>
        <button type="button" class="quiet" @click="router.push({ name: 'contacts_dashboard_index' })">
          Contacts
        </button>
      </div>
    </header>

    <div v-if="loading" class="loading"><Spinner /></div>

    <template v-else>
      <div class="stats">
        <article v-for="card in [
          { key: 'open', label: 'Open', value: counts.open, icon: 'i-lucide-message-circle' },
          { key: 'unassigned', label: 'Unassigned', value: counts.unassigned, icon: 'i-lucide-user-round' },
          { key: 'pending', label: 'Pending', value: counts.pending, icon: 'i-lucide-clock-3' },
          { key: 'resolved', label: 'Resolved', value: counts.resolved, icon: 'i-lucide-circle-check' },
          { key: 'contacts', label: 'Contacts', value: counts.contacts, icon: 'i-lucide-contact' },
          { key: 'agents', label: 'Agents online', value: availability.online.length, icon: 'i-lucide-headset' },
        ]" :key="card.key" :class="card.key">
          <Icon :icon="card.icon" class="stat-icon" />
          <strong>{{ card.value ?? '—' }}</strong>
          <span>{{ card.label }}</span>
          <em v-if="card.key === 'open' && trend">
            {{ trend.up ? '+' : '' }}{{ trend.change }}% this week
          </em>
        </article>
      </div>

      <div class="grid">
        <article class="panel chats">
          <header>
            <h2>Ongoing conversations</h2>
            <button type="button" class="link" @click="router.push({ name: 'home' })">View all</button>
          </header>
          <p v-if="!openChats.length" class="empty">No open conversations right now.</p>
          <button
            v-for="chat in openChats"
            :key="chat.id"
            type="button"
            class="chat"
            @click="openConversation(chat.id)"
          >
            <img v-if="chat.meta?.sender?.thumbnail" :src="chat.meta.sender.thumbnail" alt="" />
            <span v-else class="avatar">{{ senderName(chat).slice(0, 1) }}</span>
            <span class="who">
              <strong>{{ senderName(chat) }}</strong>
              <small>{{ preview(chat) }}</small>
            </span>
            <span class="meta">
              <em>{{ chat.meta?.assignee?.name || 'Unassigned' }}</em>
              <small>{{ chat.last_activity_at ? dynamicTime(chat.last_activity_at) : '' }}</small>
            </span>
          </button>
        </article>

        <article class="panel team">
          <h2>Team</h2>
          <ul class="presence">
            <li><i class="on" /> {{ availability.online.length }} available</li>
            <li><i class="busy" /> {{ availability.busy.length }} busy</li>
            <li><i class="off" /> {{ availability.offline.length }} offline</li>
          </ul>
          <p v-if="!workload.length" class="empty">No agents in this account yet.</p>
          <div v-for="agent in workload" :key="agent.id" class="load">
            <div>
              <strong>{{ agent.name }}</strong>
              <small>{{ agent.count }} this week</small>
            </div>
            <span><b :style="{ width: agent.width }" /></span>
          </div>
        </article>

        <article class="panel channels">
          <h2>Channels</h2>
          <p v-if="!channels.length" class="empty">No inboxes are connected yet.</p>
          <div v-for="inbox in channels" :key="inbox.id" class="channel">
            <Icon :icon="inbox.icon" />
            <span>{{ inbox.name }}</span>
            <strong>{{ inbox.count === null ? '—' : inbox.count }}</strong>
          </div>
        </article>

        <article class="panel chart">
          <header>
            <h2>Conversation volume</h2>
            <span v-if="responseLabel">First reply {{ responseLabel }}</span>
          </header>
          <p v-if="!chartPoints" class="empty">Volume appears after the report data loads.</p>
          <svg v-else viewBox="0 0 280 88" role="img" aria-label="Conversations over the last seven days">
            <polyline :points="chartPoints" />
          </svg>
          <p class="split">
            <span>{{ summary?.conversations_count ?? '—' }} new</span>
            <span>{{ summary?.resolutions_count ?? '—' }} resolved</span>
          </p>
        </article>

        <article class="panel feed">
          <h2>Recent activity</h2>
          <p v-if="!activity.length" class="empty">Nothing new yet.</p>
          <button
            v-for="item in activity"
            :key="`${item.status}-${item.id}`"
            type="button"
            class="event"
            @click="openConversation(item.id)"
          >
            <Icon :icon="item.status === 'resolved' ? 'i-lucide-circle-check' : 'i-lucide-message-circle'" />
            <span>
              <strong>{{ senderName(item) }}</strong>
              <small>{{ item.status === 'resolved' ? 'Resolved' : 'Active conversation' }}</small>
            </span>
            <em>{{ item.last_activity_at ? dynamicTime(item.last_activity_at) : '' }}</em>
          </button>
        </article>
      </div>
    </template>
  </section>
</template>

<style scoped>
.overview {
  display: flex;
  flex-direction: column;
  height: 100%;
  max-height: 100%;
  overflow: hidden;
  box-sizing: border-box;
  padding: 28px 32px 24px;
  color: #f6f5f2;
}
.overview-head,
.panel header,
.quick {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
}
.eyebrow {
  margin: 0 0 6px;
  color: #5db5e2;
  font-size: 12px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}
h1 {
  margin: 0;
  font-size: 34px;
  letter-spacing: -0.045em;
}
.lede,
.empty,
.meta small,
.who small,
.load small,
.event small,
.chart header span,
.split {
  color: #c8c4dc;
}
.lede { margin: 8px 0 0; max-width: 52ch; }
.quick button,
.panel .link {
  border: 1px solid rgba(93, 181, 226, 0.55);
  background: linear-gradient(180deg, rgba(93, 181, 226, 0.85), #5db5e2);
  color: #0a0a0b;
  border-radius: 999px;
  padding: 8px 14px;
  font-weight: 600;
}
.quick .quiet,
.panel .link {
  background: rgba(122, 115, 203, 0.16);
  color: #f6f5f2;
  border-color: rgba(122, 115, 203, 0.45);
}
.loading { display: grid; place-items: center; min-height: 240px; }
.stats,
.grid {
  display: grid;
  gap: 14px;
  margin-top: 22px;
}
.stats { flex: none; }
.grid {
  flex: 1;
  min-height: 0;
  align-items: stretch;
  grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr) minmax(0, 1fr);
  grid-template-rows: auto minmax(180px, 1fr) auto;
}
.stats { grid-template-columns: repeat(6, minmax(0, 1fr)); }
.stats article,
.panel {
  position: relative;
  overflow: hidden;
  border-radius: 22px;
  border: 1px solid rgba(154, 148, 214, 0.48);
  background:
    linear-gradient(160deg, rgba(122, 115, 203, 0.34), rgba(93, 181, 226, 0.12) 48%, rgba(18, 14, 40, 0.78));
  box-shadow: 0 1px 0 rgba(255, 255, 255, 0.16) inset, 0 18px 40px rgba(4, 6, 20, 0.28);
  backdrop-filter: blur(18px);
}
.stats article { padding: 14px 14px 16px; }
.stats strong { display: block; margin-top: 12px; font-size: 28px; letter-spacing: -0.04em; }
.stats span,
.stats em { display: block; color: #c8c4dc; font-size: 12px; font-style: normal; }
.stats .open,
.stats .pending,
.stats .contacts { background: linear-gradient(160deg, rgba(122, 115, 203, 0.48), rgba(18, 14, 40, 0.78)); }
.stats .unassigned,
.stats .resolved,
.stats .agents { background: linear-gradient(160deg, rgba(93, 181, 226, 0.28), rgba(90, 70, 160, 0.36) 55%, rgba(18, 14, 40, 0.78)); }
.stat-icon { color: #d7d2f8; }
.panel {
  height: 100%;
  box-sizing: border-box;
  padding: 18px;
}
.panel h2 { margin: 0; font-size: 16px; letter-spacing: -0.03em; }
.chats { grid-column: 1; grid-row: 1 / span 2; }
.team { grid-column: 2; grid-row: 1; }
.channels { grid-column: 3; grid-row: 1; }
.chart { grid-column: 2 / span 2; grid-row: 2; display: flex; flex-direction: column; }
.feed { grid-column: 1 / -1; grid-row: 3; }
.chats,
.team,
.channels,
.feed {
  min-height: 0;
  overflow: auto;
  scrollbar-gutter: stable;
  scrollbar-width: thin;
  scrollbar-color: rgba(93, 181, 226, 0.7) transparent;
}
.chats::-webkit-scrollbar,
.team::-webkit-scrollbar,
.channels::-webkit-scrollbar,
.feed::-webkit-scrollbar {
  width: 8px;
}
.chats::-webkit-scrollbar-thumb,
.team::-webkit-scrollbar-thumb,
.channels::-webkit-scrollbar-thumb,
.feed::-webkit-scrollbar-thumb {
  border: 2px solid transparent;
  border-radius: 999px;
  background: linear-gradient(180deg, #5db5e2, #7a73cb) padding-box;
}
.chat,
.event,
.channel,
.load,
.presence {
  display: flex;
  align-items: center;
  gap: 12px;
}
.chat,
.event {
  width: 100%;
  margin-top: 10px;
  padding: 10px;
  text-align: left;
  color: inherit;
  border-radius: 16px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  background: rgba(8, 10, 24, 0.35);
}
.chat img,
.avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  object-fit: cover;
  background: rgba(122, 115, 203, 0.35);
  display: grid;
  place-items: center;
}
.who,
.event span,
.load div { display: flex; flex-direction: column; min-width: 0; flex: 1; }
.who small,
.event small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.meta { margin-left: auto; text-align: right; }
.presence { list-style: none; padding: 12px 0 4px; margin: 0; gap: 14px; }
.presence i { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
.on { background: #5db5e2; }
.busy { background: #7a73cb; }
.off { background: #5c5d60; }
.load { margin-top: 10px; }
.load span {
  width: 88px;
  height: 6px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.08);
  overflow: hidden;
}
.load b { display: block; height: 100%; border-radius: inherit; background: linear-gradient(90deg, #5db5e2, #7a73cb); }
.channel { margin-top: 12px; }
.channel strong { margin-left: auto; }
.chart svg { width: 100%; height: 110px; margin-top: 12px; flex: 1; }
.chart polyline { fill: none; stroke: #5db5e2; stroke-width: 3; stroke-linecap: round; stroke-linejoin: round; filter: drop-shadow(0 0 6px rgba(93, 181, 226, 0.7)); }
.split { display: flex; gap: 18px; margin: 0; }
@media (max-width: 1100px) {
  .stats { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .grid { grid-template-columns: 1fr; grid-template-rows: none; }
  .chats,
  .team,
  .channels,
  .chart,
  .feed { grid-column: auto; grid-row: auto; }
}
@media (max-width: 720px) {
  .overview { padding: 18px; }
  .overview-head,
  .stats { display: grid; }
  .stats { grid-template-columns: 1fr 1fr; }
  h1 { font-size: 28px; }
}
</style>
