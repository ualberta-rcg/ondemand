'use strict';

import { appsDatatablePageLength } from './config.js';
import { dataTablesLanguage } from './datatables_i18n.js';

jQuery(function() {
  const pageLength = appsDatatablePageLength();
  $('#all-apps-table').DataTable({
    stateSave: false,
    pageLength: pageLength,
    language: dataTablesLanguage(),
  });
});
