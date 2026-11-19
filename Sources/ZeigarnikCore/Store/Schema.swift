import Foundation
import GRDB

extension Store {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE project (
                  id TEXT PRIMARY KEY, displayName TEXT NOT NULL, summary TEXT, path TEXT NOT NULL,
                  state TEXT NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, createdAt REAL NOT NULL, lastSeenAt REAL NOT NULL);
                CREATE TABLE projectIdentity (
                  projectId TEXT PRIMARY KEY REFERENCES project(id) ON DELETE CASCADE, commonDir TEXT, rootCommits TEXT, remoteURL TEXT);
                CREATE TABLE snapshot (
                  projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE, day TEXT NOT NULL, scannedAt REAL NOT NULL,
                  status TEXT, fetch TEXT, lastFetchAt REAL, lastCommitAt REAL, readme TEXT, spec TEXT, activeTasksOpen INTEGER, error TEXT,
                  PRIMARY KEY (projectId, day));
                CREATE TABLE ownerMessage (
                  agent TEXT NOT NULL, sessionId TEXT NOT NULL, ts REAL NOT NULL, cwd TEXT, source TEXT NOT NULL,
                  projectId TEXT, otherLabel TEXT, PRIMARY KEY (agent, sessionId, ts, source));
                CREATE INDEX ownerMessage_project ON ownerMessage(projectId);
                CREATE INDEX ownerMessage_cwd ON ownerMessage(cwd);
                CREATE TABLE session (
                  agent TEXT NOT NULL, sessionId TEXT NOT NULL CHECK (length(sessionId) > 0), cwd TEXT, firstSeen REAL, lastSeen REAL,
                  delegated INTEGER NOT NULL DEFAULT 0, projectId TEXT, otherLabel TEXT, PRIMARY KEY (agent, sessionId));
                CREATE TABLE fileCursor (
                  path TEXT PRIMARY KEY, inode INTEGER NOT NULL, size INTEGER NOT NULL, offset INTEGER NOT NULL,
                  headLength INTEGER NOT NULL, headHash TEXT NOT NULL);
                CREATE TABLE codexSession (sessionId TEXT PRIMARY KEY, cwd TEXT, delegated INTEGER NOT NULL, startedAt REAL);
                CREATE TABLE commitDay (projectId TEXT NOT NULL, day TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (projectId, day));
                CREATE TABLE specEvidence (projectId TEXT NOT NULL, specPath TEXT NOT NULL, json TEXT NOT NULL, scannedAt REAL NOT NULL,
                  PRIMARY KEY (projectId, specPath));
                CREATE TABLE specOverride (projectId TEXT NOT NULL, specPath TEXT NOT NULL, state TEXT NOT NULL, note TEXT,
                  PRIMARY KEY (projectId, specPath));
                """)
        }
        migrator.registerMigration("v2-project-paths") { db in
            try db.execute(sql: """
                CREATE TABLE projectPath (
                  projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE, path TEXT NOT NULL, PRIMARY KEY (projectId, path));
                INSERT OR IGNORE INTO projectPath (projectId, path) SELECT id, path FROM project;
                """)
        }
        migrator.registerMigration("v3-owner-data") { db in
            try db.execute(sql: """
                CREATE TABLE note (
                  id TEXT PRIMARY KEY, projectId TEXT NOT NULL REFERENCES project(id), day TEXT NOT NULL,
                  text TEXT NOT NULL, createdAt REAL NOT NULL);
                CREATE INDEX note_day ON note(day);
                CREATE INDEX note_project ON note(projectId);
                CREATE TABLE scheduledItem (
                  id TEXT PRIMARY KEY, projectId TEXT NOT NULL REFERENCES project(id), title TEXT NOT NULL,
                  start REAL NOT NULL, duration REAL NOT NULL, wantsCalendar INTEGER NOT NULL, eventIdentifier TEXT,
                  syncState TEXT NOT NULL, syncDetail TEXT, deletedAt REAL, createdAt REAL NOT NULL, updatedAt REAL NOT NULL);
                CREATE INDEX scheduledItem_start ON scheduledItem(start);
                CREATE TABLE calendarOp (
                  seq INTEGER PRIMARY KEY AUTOINCREMENT, itemId TEXT NOT NULL, kind TEXT NOT NULL, createdAt REAL NOT NULL);
                """)
        }
        migrator.registerMigration("v4-architecture") { db in
            try db.execute(sql: "ALTER TABLE snapshot ADD COLUMN architecture TEXT")
        }
        migrator.registerMigration("v5-repo-visibility") { db in
            try db.execute(sql: """
                CREATE TABLE repoVisibility (
                  projectId TEXT PRIMARY KEY REFERENCES project(id) ON DELETE CASCADE,
                  visibility TEXT NOT NULL, checkedAt REAL NOT NULL)
                """)
        }
        return migrator
    }
}
