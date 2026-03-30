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

});
