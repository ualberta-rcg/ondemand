import { getBoolean, storeBoolean } from '../utils';
import { OODAlertError } from '../alert';
import { t } from '../i18n';

const NOTIFICATIONS_ENABLED_KEY = 'ood_notifications_enabled';
const EXPIRATION_NOTIFIED_KEY = 'ood_expiration_notified';

export function notificationsEnabled() {
  return getBoolean(NOTIFICATIONS_ENABLED_KEY);
}

export function getNotifiedSessionIds() {
  return JSON.parse(localStorage.getItem(EXPIRATION_NOTIFIED_KEY)) || [];
}

export function storeNotifiedSessionIds(sessions) {
  localStorage.setItem(EXPIRATION_NOTIFIED_KEY, JSON.stringify(sessions));
}

export function pruneNotifiedSessionIds(sessions, notifiedSessionIds) {
  const currentNotifiedIds = []

  notifiedSessionIds.forEach((sessionId) => {
    if (sessions.has(sessionId)) {
      currentNotifiedIds.push(sessionId);
    }
  });

  storeNotifiedSessionIds(currentNotifiedIds);
}

export function setupNotificationToggle(toggleElementId) {
  const notifToggleBtn = document.getElementById(toggleElementId);
  if (!notifToggleBtn) return;

  if (!('Notification' in window) || Notification.permission !== 'granted') {
    notifToggleBtn.checked = false;
  } else {
    notifToggleBtn.checked = getBoolean(NOTIFICATIONS_ENABLED_KEY);
  }
  storeBoolean(NOTIFICATIONS_ENABLED_KEY, notifToggleBtn.checked);

  notifToggleBtn.addEventListener('change', async (event) => {
    if (Notification.permission !== 'granted') {
      try {
        const permission = await Notification.requestPermission();
        if (permission !== 'granted') {
          event.target.checked = false;
          OODAlertError(t('batch_connect.allow_notifications'));
        }
      } catch (error) {
        OODAlertError(t('batch_connect.notification_permission_error'), error);
      }
    }
    storeBoolean(NOTIFICATIONS_ENABLED_KEY, event.target.checked);
  });
}
