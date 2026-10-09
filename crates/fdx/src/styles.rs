use slugline_fountain::{emphasis, Emphasis, EmphasisRun};

pub(crate) fn literal(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len());
    append_literal(&mut escaped, text);
    escaped
}

fn append_literal(escaped: &mut String, text: &str) {
    for c in text.chars() {
        if matches!(c, '*' | '_' | '\\') {
            escaped.push('\\');
        }
        escaped.push(c);
    }
}

pub(crate) fn printable(text: &str) -> Vec<EmphasisRun> {
    let rows: Vec<_> = text.split('\n').collect();
    join_rows(emphasis::scan(&rows).into_iter())
}

pub(crate) fn printable_title(text: &str) -> Vec<EmphasisRun> {
    join_rows(text.split('\n').map(emphasis::scan_row))
}

fn join_rows(rows: impl Iterator<Item = Vec<EmphasisRun>>) -> Vec<EmphasisRun> {
    let mut result = Vec::new();
    for (index, row) in rows.enumerate() {
        if index != 0 {
            push(&mut result, "\n", Emphasis::PLAIN);
        }
        for run in row {
            if let Some(last) = result
                .last_mut()
                .filter(|last| last.emphasis == run.emphasis)
            {
                last.text.push_str(&run.text);
            } else {
                result.push(run);
            }
        }
    }
    result
}

pub(crate) fn push(runs: &mut Vec<EmphasisRun>, text: &str, style: Emphasis) {
    if text.is_empty() {
        return;
    }
    if let Some(last) = runs.last_mut().filter(|last| last.emphasis == style) {
        last.text.push_str(text);
    } else {
        runs.push(EmphasisRun {
            text: text.to_owned(),
            emphasis: style,
        });
    }
}

pub(crate) fn text(runs: &[EmphasisRun]) -> String {
    runs.iter().map(|run| run.text.as_str()).collect()
}

fn cells(runs: &[EmphasisRun]) -> impl Iterator<Item = (char, Emphasis)> + '_ {
    runs.iter()
        .flat_map(|run| run.text.chars().map(move |c| (c, run.emphasis)))
}
pub(crate) fn equivalent(left: &[EmphasisRun], right: &[EmphasisRun]) -> bool {
    cells(left).eq(cells(right))
}

pub(crate) fn markup(runs: &[EmphasisRun], warnings: &mut Vec<String>) -> String {
    let mut result = String::new();
    for run in runs {
        // Fountain cannot attach paired emphasis to leading/trailing whitespace.
        // Line boundaries are outside spans, matching the shared scanner.
        for (index, line) in run.text.split('\n').enumerate() {
            if index != 0 {
                result.push('\n');
            }
            let core = line.trim_matches(char::is_whitespace);
            if core.is_empty() {
                append_literal(&mut result, line);
                continue;
            }
            let start = line.len() - line.trim_start_matches(char::is_whitespace).len();
            let end = start + core.len();
            append_literal(&mut result, &line[..start]);
            let stars = match (run.emphasis.bold, run.emphasis.italic) {
                (true, true) => "***",
                (true, false) => "**",
                (false, true) => "*",
                _ => "",
            };
            result.push_str(stars);
            if run.emphasis.underline {
                result.push('_');
            }
            append_literal(&mut result, core);
            if run.emphasis.underline {
                result.push('_');
            }
            result.push_str(stars);
            append_literal(&mut result, &line[end..]);
        }
    }
    let resolved = printable(&result);
    if !resolved
        .iter()
        .flat_map(|run| run.text.chars())
        .eq(runs.iter().flat_map(|run| run.text.chars()))
    {
        warnings.push("Text styling could not be represented by Fountain pairing; styling flattened, all printable text retained.".into());
        return literal(&text(runs));
    }
    if !equivalent(&resolved, runs) {
        warnings.push("Text style boundaries normalized to Fountain emphasis pairing; all printable text retained.".into());
    }
    result
}
