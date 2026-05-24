export interface BuiltinItem {
  name: string;        // e.g. "concat"
  modulePath: string;  // e.g. "Str" or "Num.U64"
  fullName: string;    // e.g. "Str.concat"
  signature: string;   // type signature including any `where` lines
  docs: string;        // accumulated `## ...` doc lines
  line: number;        // 1-based line in Builtin.roc
}

export interface BuiltinIndex {
  items: BuiltinItem[];
  byFullName: Map<string, BuiltinItem>;
  byName: Map<string, BuiltinItem[]>;
  modulePaths: Set<string>;
}

function countLeadingTabs(line: string): number {
  let n = 0;
  while (n < line.length && line[n] === "\t") n++;
  return n;
}

export function parseBuiltin(content: string): BuiltinIndex {
  const lines = content.split("\n");
  const items: BuiltinItem[] = [];
  const stack: { name: string; indent: number }[] = [];
  let pendingDecl: { name: string; indent: number } | null = null;
  let pendingDocs: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    const indent = countLeadingTabs(line);

    if (trimmed === "") continue;

    if (trimmed.startsWith("##")) {
      const text = trimmed === "##" ? "" : trimmed.replace(/^##\s?/, "");
      pendingDocs.push(text);
      continue;
    }

    if (trimmed === "}" && stack.length > 0 && indent === stack[stack.length - 1].indent) {
      stack.pop();
      pendingDocs = [];
      continue;
    }

    const declMatch = trimmed.match(/^([A-Z]\w*)(?:\([^)]*\))?\s+(::|:=)(?=\s|$)/);
    if (declMatch) {
      pendingDecl = { name: declMatch[1], indent };
    }

    if (/\.\{\s*$/.test(trimmed) && pendingDecl) {
      stack.push({ name: pendingDecl.name, indent: pendingDecl.indent });
      pendingDecl = null;
      pendingDocs = [];
      continue;
    }

    const sigMatch = trimmed.match(/^([a-z_]\w*!?)\s+:\s+(.+)$/);
    if (sigMatch && stack.length > 0 && indent > stack[stack.length - 1].indent) {
      let sig = sigMatch[2];
      let j = i + 1;
      while (j < lines.length) {
        const next = lines[j];
        const nextTrim = next.trim();
        if (nextTrim === "") break;
        const nextIndent = countLeadingTabs(next);
        if (nextIndent > indent && !nextTrim.startsWith("##")) {
          sig += "\n" + next;
          j++;
        } else {
          break;
        }
      }
      const modulePath = stack.map((s) => s.name).filter((n) => n !== "Builtin").join(".");
      const fullName = modulePath ? `${modulePath}.${sigMatch[1]}` : sigMatch[1];
      items.push({
        name: sigMatch[1],
        modulePath,
        fullName,
        signature: sig,
        docs: pendingDocs.join("\n").trim(),
        line: i + 1,
      });
      pendingDocs = [];
      continue;
    }

    pendingDocs = [];
  }

  const byFullName = new Map<string, BuiltinItem>();
  const byName = new Map<string, BuiltinItem[]>();
  const modulePaths = new Set<string>();
  for (const item of items) {
    byFullName.set(item.fullName, item);
    const bucket = byName.get(item.name);
    if (bucket) bucket.push(item);
    else byName.set(item.name, [item]);
    if (item.modulePath) modulePaths.add(item.modulePath);
  }

  return { items, byFullName, byName, modulePaths };
}
