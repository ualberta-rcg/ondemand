import { nsfAccessAnnouncementsUrl } from './config';
import { fetchNsfAccessJson, mountNsfAccessAccordion } from './nsf_access_widget';
import { t } from './i18n';

document.addEventListener('DOMContentLoaded', () => {
  listAnnouncements();
});

function listAnnouncements() {
  fetchNsfAccessJson(nsfAccessAnnouncementsUrl())
    .then(announcements => {
      mountNsfAccessAccordion({
        elementId: 'nsf_access_announcements',
        getContainerId: () => 'nsf_access_announcements_container',
        items: filterAnnouncements(announcements),
        getIdPrefix: () => 'nsf_access_announcement',
        getItemId: (announcement) => announcement['uuid'],
        getTitle: (announcement) => announcement['title'],
        getDate: (announcement) => announcement['published_date'],
        getBodyHtml: (announcement) => announcement['body'],
        getLink: (announcement) => {
          const url = announcement['url'];
          if(url !== undefined && url !== "") {
            return { href: url, text: t('nsf_access.read_more') };
          }

          return null;
        },
      });
    });
}

function filterAnnouncements(announcements) {
  if (!announcements) {
    return [];
  }

  const pastLimit = new Date();
  pastLimit.setMonth(pastLimit.getMonth() - 1);

  return announcements.filter((announcement) => {
    const publishedDate = new Date(announcement['published_date']);
    return publishedDate > pastLimit;
  })
}
