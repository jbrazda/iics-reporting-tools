/* IICS Reporting Tools – shared client-side behaviour
 *
 * Requires: jQuery 2.x, jQuery UI 1.11.x, DataTables (on table pages)
 */
$(function () {

    // ── Databases table ───────────────────────────────────────────────────────
    if ($('#databases_table').length) {
        $('#databases_table').DataTable({
            jQueryUI   : true,
            scrollX    : true,
            scrollY    : false,
            colReorder : true,
            responsive : true,
            lengthMenu : [[10, 25, 50, 100, -1], [10, 25, 50, 100, 'All']],
            paging     : true,
            dom        : 'BlfrtFip',
            columnDefs : [{
                targets   : [1, 2, 3],
                className : 'dt-body-right dt-body-nowrap'
            }],
            buttons: [
                'colvis',
                'copy',
                { extend: 'excel', filename: 'databases' },
                'csvHtml5',
                'print'
            ]
        });
        $('div.tableWrapper').addClass('tableWrapperFitContents');
    }

    // ── Upload package dialog ─────────────────────────────────────────────────
    if ($('#upload-dialog').length) {
        $('#upload-dialog').dialog({
            autoOpen : false,
            modal    : true,
            title    : 'Upload IICS Export Package',
            width    : 520,
            buttons  : [
                {
                    text  : 'Upload',
                    icons : { primary: 'ui-icon-arrowthickstop-1-n' },
                    click : function () { $('#upload-form').submit(); }
                },
                {
                    text  : 'Cancel',
                    click : function () { $(this).dialog('close'); }
                }
            ]
        });

        $('#btn-upload-package').button().on('click', function () {
            $('#upload-dialog').dialog('open');
        });

        $('#uploadFile').on('change', function () {
            var name = this.files[0] ? this.files[0].name : '';
            $('#uploadDbName').val(
                name.replace(/\.zip$/i, '').replace(/[^a-zA-Z0-9_\-]/g, '_')
            );
        });
    }

    // ── Replace-database confirmation dialog ──────────────────────────────────
    if ($('#confirm-dialog').length) {
        $('#confirm-dialog').dialog({
            autoOpen      : true,
            modal         : true,
            title         : 'Replace Existing Database?',
            width         : 480,
            closeOnEscape : false,
            open          : function (event, ui) {
                /* hide the default ✕ close button – Cancel button does the job */
                $(this).closest('.ui-dialog').find('.ui-dialog-titlebar-close').hide();
            },
            buttons : [
                {
                    text  : 'Replace',
                    icons : { primary: 'ui-icon-alert' },
                    click : function () { $('#confirm-form').submit(); }
                },
                {
                    text  : 'Cancel',
                    click : function () { window.location.href = '/iics/database'; }
                }
            ]
        });
    }

    // ── jQuery UI buttons in header ───────────────────────────────────────────
    $('.ui-header-button').button();

    // ── CDI asset sub-tabs ────────────────────────────────────────────────────
    if ($('#cdi-tabs').length) {
        $('#cdi-tabs').tabs({
            activate: function (event, ui) {
                // Initialize DataTable lazily when its tab is first shown
                var tableId = ui.newPanel.find('table.display').attr('id');
                if (tableId && !$.fn.DataTable.isDataTable('#' + tableId)) {
                    $('#' + tableId).DataTable({
                        jQueryUI   : true,
                        scrollX    : true,
                        paging     : true,
                        lengthMenu : [[25, 50, 100, -1], [25, 50, 100, 'All']],
                        dom        : 'BlfrtFip',
                        buttons    : ['colvis', 'copy', 'csvHtml5', 'print']
                    });
                }
            }
        });
        // Init first CDI tab's table immediately
        var $firstCdiTable = $('#cdi-tabs .ui-tabs-panel:first table.display');
        if ($firstCdiTable.length && !$.fn.DataTable.isDataTable($firstCdiTable)) {
            $firstCdiTable.DataTable({
                jQueryUI   : true,
                scrollX    : true,
                paging     : true,
                lengthMenu : [[25, 50, 100, -1], [25, 50, 100, 'All']],
                dom        : 'BlfrtFip',
                buttons    : ['colvis', 'copy', 'csvHtml5', 'print']
            });
        }
    }

});

// ============================================================
// vis.js dependency / impact graph rendering
// ============================================================

IICS = window.IICS || {};

/** Group-to-color map matching CSS class colours above. */
IICS.graphColors = {
    root          : { background: '#2a6496', border: '#1e4d79', font: { color: '#fff' } },
    process       : { background: '#d9edf7', border: '#bce8f1' },
    guide         : { background: '#dff0d8', border: '#d6e9c6' },
    connection    : { background: '#fcf8e3', border: '#faebcc' },
    connector     : { background: '#f2dede', border: '#ebccd1' },
    processObject : { background: '#e8d5f5', border: '#c9a3e8' },
    taskflow      : { background: '#d5e8d4', border: '#82b366' },
    'cdi-mapping' : { background: '#dae8fc', border: '#6c8ebf' },
    'cdi-task'    : { background: '#fff2cc', border: '#d6b656' }
};

/** Stores vis.Network instances keyed by container element id. */
IICS._graphs = {};

/**
 * Fetches graph data from the JSON API and renders a vis.js Network.
 *
 * @param {string}  database   database name
 * @param {string}  guid       design GUID
 * @param {Element} container  DOM element for the graph canvas
 * @param {Element} statusEl   DOM element for status messages
 * @param {string}  type       'deps' or 'impact'
 */
IICS._renderGraph = function (database, guid, container, statusEl, type) {
    if (!container || container._visInitialized) { return; }

    var endpoint = type === 'impact'
        ? '/iics/api/design/impact'
        : '/iics/api/design/dependencies';

    statusEl.textContent = 'Loading graph…';

    fetch(endpoint + '?database=' + encodeURIComponent(database) +
                      '&guid='     + encodeURIComponent(guid))
        .then(function (r) { return r.json(); })
        .then(function (data) {
            if (data.error) {
                statusEl.textContent = 'Error: ' + data.error;
                return;
            }
            statusEl.textContent = data.cached
                ? '(' + data.nodes.length + ' nodes, cached)'
                : '(' + data.nodes.length + ' nodes, computed live)';

            // Attach color options based on group
            var nodes = (data.nodes || []).map(function (n) {
                var color = IICS.graphColors[n.group] || {};
                return Object.assign({}, n, {
                    color : color,
                    font  : color.font || {}
                });
            });

            var visNodes = new vis.DataSet(nodes);
            var visEdges = new vis.DataSet(data.edges || []);
            var network  = new vis.Network(container, { nodes: visNodes, edges: visEdges }, {
                layout: {
                    hierarchical: {
                        enabled   : true,
                        direction : 'LR',
                        sortMethod: 'directed'
                    }
                },
                edges : { arrows: 'to', smooth: { type: 'cubicBezier' } },
                physics: { enabled: false }
            });

            IICS._graphs[container.id] = { network: network, hierarchical: true };
            container._visInitialized = true;
        })
        .catch(function (err) {
            statusEl.textContent = 'Failed to load graph: ' + err.message;
        });
};

/** Initializes the dependency graph for a design detail page. */
IICS.initDepGraph = function (database, guid, container, statusEl) {
    IICS._renderGraph(database, guid, container, statusEl, 'deps');
};

/** Initializes the impact graph for a design detail page. */
IICS.initImpactGraph = function (database, guid, container, statusEl) {
    IICS._renderGraph(database, guid, container, statusEl, 'impact');
};

/**
 * Toggles a vis.js graph between hierarchical (LR) and force-directed layout.
 *
 * @param {string} containerId  id of the graph container element
 */
IICS.toggleGraphLayout = function (containerId) {
    var entry = IICS._graphs[containerId];
    if (!entry) { return; }
    var newHierarchical = !entry.hierarchical;
    entry.hierarchical  = newHierarchical;
    entry.network.setOptions({
        layout : { hierarchical: { enabled: newHierarchical } },
        physics: { enabled: !newHierarchical }
    });
};
