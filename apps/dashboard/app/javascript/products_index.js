'use strict';

import 'datatables.net';
import 'datatables.net-bs5/js/dataTables.bootstrap5';
import { dataTablesLanguage } from './datatables_i18n.js';

jQuery(function(){
  $('#productTable').DataTable({
    language: dataTablesLanguage(),
  });
});
