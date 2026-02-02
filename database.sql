-- database.sql
-- Dialect: PostgreSQL

-- Можно включить расширение для UUID, но по заданию достаточно bigint/serial.
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================
-- Core tables
-- =========================

CREATE TABLE programs (
    id          BIGSERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    price       INTEGER NOT NULL CHECK (price >= 0),
    program_type TEXT NOT NULL, -- например: 'intensive', 'profession'
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE modules (
    id          BIGSERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE courses (
    id          BIGSERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE lessons (
    id          BIGSERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    content     TEXT,
    video_url   TEXT,
    position    INTEGER NOT NULL CHECK (position > 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    course_id   BIGINT NOT NULL REFERENCES courses(id),
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE,

    -- Один и тот же номер урока в рамках одного курса не должен повторяться
    CONSTRAINT lessons_course_id_position_unique UNIQUE (course_id, position)
);

-- =========================
-- Many-to-many relations
-- =========================

-- Программа -> Модули (многие-ко-многим)
CREATE TABLE program_modules (
    program_id  BIGINT NOT NULL REFERENCES programs(id),
    module_id   BIGINT NOT NULL REFERENCES modules(id),
    PRIMARY KEY (program_id, module_id)
);

-- Модуль -> Курсы (многие-ко-многим)
CREATE TABLE module_courses (
    module_id   BIGINT NOT NULL REFERENCES modules(id),
    course_id   BIGINT NOT NULL REFERENCES courses(id),
    PRIMARY KEY (module_id, course_id)
);

-- (Опционально, но полезно) Программа -> Курсы напрямую не требуется по ТЗ, поэтому не добавляем.

-- =========================
-- Indexes (не обязательно для прохождения, но полезно)
-- =========================

CREATE INDEX lessons_course_id_idx ON lessons(course_id);
CREATE INDEX program_modules_module_id_idx ON program_modules(module_id);
CREATE INDEX module_courses_course_id_idx ON module_courses(course_id);
-- =========================
-- Users & Teaching Groups
-- =========================

CREATE TABLE teaching_groups (
    id          BIGSERIAL PRIMARY KEY,
    slug        TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE users (
    id                BIGSERIAL PRIMARY KEY,
    name              TEXT NOT NULL,
    email             TEXT NOT NULL UNIQUE,
    password_hash     TEXT NOT NULL,
    teaching_group_id BIGINT NOT NULL REFERENCES teaching_groups(id),
    role              TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT users_role_check CHECK (role IN ('student', 'teacher', 'admin'))
);

CREATE INDEX users_teaching_group_id_idx ON users(teaching_group_id);

-- =========================
-- Enums for states
-- =========================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'enrollment_status') THEN
        CREATE TYPE enrollment_status AS ENUM ('active', 'pending', 'cancelled', 'completed');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status') THEN
        CREATE TYPE payment_status AS ENUM ('pending', 'paid', 'failed', 'refunded');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'program_completion_status') THEN
        CREATE TYPE program_completion_status AS ENUM ('active', 'completed', 'pending', 'cancelled');
    END IF;
END$$;

-- =========================
-- Enrollments
-- =========================

CREATE TABLE enrollments (
    id         BIGSERIAL PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users(id),
    program_id BIGINT NOT NULL REFERENCES programs(id),
    status     enrollment_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT enrollments_user_program_unique UNIQUE (user_id, program_id)
);

CREATE INDEX enrollments_user_id_idx ON enrollments(user_id);
CREATE INDEX enrollments_program_id_idx ON enrollments(program_id);

-- =========================
-- Payments
-- =========================

CREATE TABLE payments (
    id            BIGSERIAL PRIMARY KEY,
    enrollment_id BIGINT NOT NULL REFERENCES enrollments(id),
    amount        INTEGER NOT NULL CHECK (amount > 0),
    status        payment_status NOT NULL DEFAULT 'pending',
    paid_at       TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX payments_enrollment_id_idx ON payments(enrollment_id);

-- =========================
-- Program completions (progress)
-- =========================

CREATE TABLE program_completions (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id),
    program_id  BIGINT NOT NULL REFERENCES programs(id),
    status      program_completion_status NOT NULL DEFAULT 'pending',
    started_at  TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT program_completions_user_program_unique UNIQUE (user_id, program_id),
    CONSTRAINT program_completions_dates_check CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at)
);

CREATE INDEX program_completions_user_id_idx ON program_completions(user_id);
CREATE INDEX program_completions_program_id_idx ON program_completions(program_id);

-- =========================
-- Certificates
-- =========================

CREATE TABLE certificates (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id),
    program_id  BIGINT NOT NULL REFERENCES programs(id),
    url         TEXT NOT NULL,
    issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT certificates_user_program_unique UNIQUE (user_id, program_id)
);

CREATE INDEX certificates_user_id_idx ON certificates(user_id);
CREATE INDEX certificates_program_id_idx ON certificates(program_id);
-- =========================
-- Quizzes
-- =========================

CREATE TABLE quizzes (
    id          BIGSERIAL PRIMARY KEY,
    lesson_id   BIGINT NOT NULL REFERENCES lessons(id),
    title       TEXT NOT NULL,
    content     JSONB NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX quizzes_lesson_id_idx ON quizzes(lesson_id);

-- =========================
-- Exercises
-- =========================

CREATE TABLE exercises (
    id          BIGSERIAL PRIMARY KEY,
    lesson_id   BIGINT NOT NULL REFERENCES lessons(id),
    title       TEXT NOT NULL,
    url         TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX exercises_lesson_id_idx ON exercises(lesson_id);
-- =========================
-- Quizzes
-- =========================

CREATE TABLE quizzes (
    id          BIGSERIAL PRIMARY KEY,
    lesson_id   BIGINT NOT NULL REFERENCES lessons(id),
    title       TEXT NOT NULL,
    content     JSONB NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX quizzes_lesson_id_idx ON quizzes(lesson_id);

-- =========================
-- Exercises
-- =========================

CREATE TABLE exercises (
    id          BIGSERIAL PRIMARY KEY,
    lesson_id   BIGINT NOT NULL REFERENCES lessons(id),
    title       TEXT NOT NULL,
    url         TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX exercises_lesson_id_idx ON exercises(lesson_id);
-- =========================
-- Quizzes
-- =========================

CREATE TABLE quizzes (
    id          BIGSERIAL PRIMARY KEY,
    lesson_id   BIGINT NOT NULL REFERENCES lessons(id),
    title       TEXT NOT NULL,
    content     JSONB NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX quizzes_lesson_id_idx ON quizzes(lesson_id);

-- =========================
-- Exercises
-- =========================

CREATE TABLE exercises (
    id          BIGSERIAL PRIMARY KEY,
    lesson_id   BIGINT NOT NULL REFERENCES lessons(id),
    title       TEXT NOT NULL,
    url         TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX exercises_lesson_id_idx ON exercises(lesson_id);
-- =========================
-- Quizzes
-- =========================

CREATE TABLE quizzes (
    id          BIGSERIAL PRIMARY KEY,
    lesson_id   BIGINT NOT NULL REFERENCES lessons(id),
    title       TEXT NOT NULL,
    content     JSONB NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX quizzes_lesson_id_idx ON quizzes(lesson_id);

-- =========================
-- Exercises
-- =========================

CREATE TABLE exercises (
    id          BIGSERIAL PRIMARY KEY,
    lesson_id   BIGINT NOT NULL REFERENCES lessons(id),
    title       TEXT NOT NULL,
    url         TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX exercises_lesson_id_idx ON exercises(lesson_id);
-- =========================
-- Blog status enum
-- =========================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'blog_status') THEN
        CREATE TYPE blog_status AS ENUM ('created', 'in moderation', 'published', 'archived');
    END IF;
END$$;

-- =========================
-- Discussions (threaded messages / tree)
-- =========================

CREATE TABLE discussions (
    id          BIGSERIAL PRIMARY KEY,
    lesson_id   BIGINT NOT NULL REFERENCES lessons(id),
    parent_id   BIGINT REFERENCES discussions(id),
    body        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX discussions_lesson_id_idx ON discussions(lesson_id);
CREATE INDEX discussions_parent_id_idx ON discussions(parent_id);

-- =========================
-- Blog
-- =========================

CREATE TABLE blog (
    id          BIGSERIAL PRIMARY KEY,
    student_id  BIGINT NOT NULL REFERENCES users(id),
    title       TEXT NOT NULL,
    body        TEXT NOT NULL,
    status      blog_status NOT NULL DEFAULT 'created',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX blog_student_id_idx ON blog(student_id);
CREATE INDEX blog_status_idx ON blog(status);




